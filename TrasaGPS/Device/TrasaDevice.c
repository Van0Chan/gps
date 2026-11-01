// Prepojenie na vývojárske služby iPhonu cez knižnicu idevice.
// Postup zodpovedá oficiálnym príkladom idevice (ffi/examples/location_simulation.c
// a ffi/examples/mount_personalized.c).

#include "TrasaDevice.h"
#include "idevice.h"

#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct TrasaDevice {
  AdapterHandle *adapter;
  RemoteServerHandle *server;
  LocationSimulationHandle *location;
};

static char *dup_string(const char *s) {
  size_t n = strlen(s) + 1;
  char *out = malloc(n);
  if (out) memcpy(out, s, n);
  return out;
}

static char *take_error(IdeviceFfiError *err, const char *step) {
  if (err == NULL) return NULL;
  const char *msg = err->message ? err->message : "neznáma chyba";
  size_t n = strlen(step) + strlen(msg) + 32;
  char *out = malloc(n);
  if (out) snprintf(out, n, "%s [%d]: %s", step, err->code, msg);
  idevice_error_free(err);
  return out;
}

static void noop_progress(size_t progress, size_t total, void *context) {
  (void)progress;
  (void)total;
  (void)context;
}

void trasa_init(uint64_t timeout_secs) { idevice_set_global_timeout(timeout_secs); }

void trasa_string_free(char *string) { free(string); }

static char *make_provider(const char *ip, const uint8_t *pairing, size_t pairing_len,
                           IdeviceProviderHandle **out) {
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_len = sizeof(addr);
  addr.sin_family = AF_INET;
  addr.sin_port = htons(LOCKDOWN_PORT);
  if (inet_pton(AF_INET, ip, &addr.sin_addr) != 1) {
    return dup_string("Neplatná IP adresa zariadenia");
  }

  IdevicePairingFile *pairing_file = NULL;
  IdeviceFfiError *err = idevice_pairing_file_from_bytes(pairing, pairing_len, &pairing_file);
  if (err != NULL) return take_error(err, "Pairing file sa nedá načítať");

  // pairing_file je pri úspechu skonzumovaný providerom
  err = idevice_tcp_provider_new((struct sockaddr *)&addr, pairing_file, "TrasaGPS", out);
  if (err != NULL) {
    idevice_pairing_file_free(pairing_file);
    return take_error(err, "TCP provider");
  }
  return NULL;
}

char *trasa_ddi_status(const char *ip, const uint8_t *pairing, size_t pairing_len,
                       int *mounted, uint64_t *unique_chip_id) {
  IdeviceProviderHandle *provider = NULL;
  char *e = make_provider(ip, pairing, pairing_len, &provider);
  if (e != NULL) return e;

  LockdowndClientHandle *lockdown = NULL;
  IdeviceFfiError *err = lockdownd_connect(provider, &lockdown);
  if (err != NULL) {
    idevice_provider_free(provider);
    return take_error(err, "Spojenie so zariadením zlyhalo (je zapnutá LocalDevVPN?)");
  }

  IdevicePairingFile *session_pairing = NULL;
  err = idevice_pairing_file_from_bytes(pairing, pairing_len, &session_pairing);
  if (err == NULL) {
    err = lockdownd_start_session(lockdown, session_pairing);
    idevice_pairing_file_free(session_pairing);
  }
  if (err != NULL) {
    lockdownd_client_free(lockdown);
    idevice_provider_free(provider);
    return take_error(err, "Pairing file nepatrí tomuto iPhonu alebo je neplatný");
  }

  plist_t chip_id = NULL;
  err = lockdownd_get_value(lockdown, "UniqueChipID", NULL, &chip_id);
  lockdownd_client_free(lockdown);
  if (err != NULL) {
    idevice_provider_free(provider);
    return take_error(err, "UniqueChipID");
  }
  uint64_t value = 0;
  plist_get_uint_val(chip_id, &value);
  plist_free(chip_id);
  *unique_chip_id = value;

  ImageMounterHandle *mounter = NULL;
  err = image_mounter_connect(provider, &mounter);
  if (err != NULL) {
    idevice_provider_free(provider);
    return take_error(err, "Image mounter (je zapnutý Režim pre vývojárov?)");
  }

  plist_t *devices = NULL;
  size_t devices_len = 0;
  err = image_mounter_copy_devices(mounter, &devices, &devices_len);
  image_mounter_free(mounter);
  idevice_provider_free(provider);
  if (err != NULL) return take_error(err, "Zoznam pripojených obrazov");

  idevice_plist_array_free(devices, devices_len);
  *mounted = devices_len > 0 ? 1 : 0;
  return NULL;
}

char *trasa_mount_ddi(const char *ip, const uint8_t *pairing, size_t pairing_len,
                      const uint8_t *image, size_t image_len,
                      const uint8_t *trustcache, size_t trustcache_len,
                      const uint8_t *manifest, size_t manifest_len,
                      uint64_t unique_chip_id, trasa_progress_cb callback, void *context) {
  IdeviceProviderHandle *provider = NULL;
  char *e = make_provider(ip, pairing, pairing_len, &provider);
  if (e != NULL) return e;

  ImageMounterHandle *mounter = NULL;
  IdeviceFfiError *err = image_mounter_connect(provider, &mounter);
  if (err != NULL) {
    idevice_provider_free(provider);
    return take_error(err, "Image mounter");
  }

  err = image_mounter_mount_personalized_with_callback(
      mounter, provider, image, image_len, trustcache, trustcache_len, manifest, manifest_len,
      NULL, unique_chip_id, callback ? callback : noop_progress, context);

  image_mounter_free(mounter);
  idevice_provider_free(provider);
  return take_error(err, "Pripojenie Developer Disk Image zlyhalo");
}

char *trasa_connect(const char *ip, const uint8_t *pairing, size_t pairing_len, TrasaDevice **out) {
  IdeviceProviderHandle *provider = NULL;
  char *e = make_provider(ip, pairing, pairing_len, &provider);
  if (e != NULL) return e;

  CoreDeviceProxyHandle *core_device = NULL;
  IdeviceFfiError *err = core_device_proxy_connect(provider, &core_device);
  idevice_provider_free(provider);
  if (err != NULL) return take_error(err, "CoreDeviceProxy");

  uint16_t rsd_port = 0;
  err = core_device_proxy_get_server_rsd_port(core_device, &rsd_port);
  if (err != NULL) {
    core_device_proxy_free(core_device);
    return take_error(err, "RSD port");
  }

  // core_device je skonzumovaný
  AdapterHandle *adapter = NULL;
  err = core_device_proxy_create_tcp_adapter(core_device, &adapter);
  if (err != NULL) return take_error(err, "Softvérový tunel");

  ReadWriteOpaque *stream = NULL;
  err = adapter_connect(adapter, rsd_port, &stream);
  if (err != NULL) {
    adapter_free(adapter);
    return take_error(err, "Pripojenie na RSD");
  }

  // stream je skonzumovaný
  RsdHandshakeHandle *handshake = NULL;
  err = rsd_handshake_new(stream, &handshake);
  if (err != NULL) {
    adapter_free(adapter);
    return take_error(err, "RSD handshake");
  }

  RemoteServerHandle *server = NULL;
  err = remote_server_connect_rsd(adapter, handshake, &server);
  rsd_handshake_free(handshake);
  if (err != NULL) {
    adapter_free(adapter);
    return take_error(err, "Vývojárske služby (DVT) – je pripojený Developer Disk Image?");
  }

  LocationSimulationHandle *location = NULL;
  err = location_simulation_new(server, &location);
  if (err != NULL) {
    remote_server_free(server);
    adapter_free(adapter);
    return take_error(err, "Služba simulácie polohy");
  }

  TrasaDevice *device = calloc(1, sizeof(TrasaDevice));
  if (device == NULL) {
    location_simulation_free(location);
    remote_server_free(server);
    adapter_free(adapter);
    return dup_string("Nedostatok pamäte");
  }
  device->adapter = adapter;
  device->server = server;
  device->location = location;
  *out = device;
  return NULL;
}

char *trasa_set_location(TrasaDevice *device, double latitude, double longitude) {
  if (device == NULL) return dup_string("Zariadenie nie je pripojené");
  return take_error(location_simulation_set(device->location, latitude, longitude),
                    "Nastavenie polohy");
}

char *trasa_clear_location(TrasaDevice *device) {
  if (device == NULL) return dup_string("Zariadenie nie je pripojené");
  return take_error(location_simulation_clear(device->location), "Obnovenie polohy");
}

void trasa_free(TrasaDevice *device) {
  if (device == NULL) return;
  location_simulation_free(device->location);
  remote_server_free(device->server);
  adapter_free(device->adapter);
  free(device);
}
