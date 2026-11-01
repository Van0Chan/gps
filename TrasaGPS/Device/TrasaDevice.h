// Jednoduché C rozhranie nad knižnicou idevice (https://github.com/jkcoxson/idevice).
// Swift volá iba tieto funkcie; všetky musia bežať na tom istom vlákne.
#ifndef TRASA_DEVICE_H
#define TRASA_DEVICE_H

#include <stddef.h>
#include <stdint.h>

typedef struct TrasaDevice TrasaDevice;
typedef void (*trasa_progress_cb)(size_t progress, size_t total, void *context);

/// Všetky funkcie vracajú NULL pri úspechu, inak text chyby (uvoľniť cez trasa_string_free).

void trasa_init(uint64_t timeout_secs);

char *trasa_ddi_status(const char *ip, const uint8_t *pairing, size_t pairing_len,
                       int *mounted, uint64_t *unique_chip_id);

char *trasa_mount_ddi(const char *ip, const uint8_t *pairing, size_t pairing_len,
                      const uint8_t *image, size_t image_len,
                      const uint8_t *trustcache, size_t trustcache_len,
                      const uint8_t *manifest, size_t manifest_len,
                      uint64_t unique_chip_id, trasa_progress_cb callback, void *context);

char *trasa_connect(const char *ip, const uint8_t *pairing, size_t pairing_len, TrasaDevice **out);
char *trasa_set_location(TrasaDevice *device, double latitude, double longitude);
char *trasa_clear_location(TrasaDevice *device);
void trasa_free(TrasaDevice *device);

void trasa_string_free(char *string);

#endif
