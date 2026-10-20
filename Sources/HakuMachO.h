#ifndef HAKU_MACHO_H
#define HAKU_MACHO_H
#include <stddef.h>
#include <stdint.h>
#define HAKU_MAX_SLICES 8
#define HAKU_MAX_RANGES 4
typedef struct {
    uint64_t offset, size, cryptid_offset;
    uint32_t cryptid;
} HakuCryptRange;
typedef struct {
    uint64_t offset, size;
    uint32_t cpu_type, cpu_subtype;
    uint8_t uuid[16];
    int has_uuid;
    unsigned range_count;
    HakuCryptRange ranges[HAKU_MAX_RANGES];
} HakuSlice;
typedef struct { unsigned count; HakuSlice slices[HAKU_MAX_SLICES]; } HakuMachO;
int haku_parse_macho(const void *bytes, size_t length, HakuMachO *result, char *error, size_t error_size);
int haku_validate_transition(const void *original, const void *derived, size_t length, char *error, size_t error_size);
void haku_uuid_string(const uint8_t uuid[16], char output[33]);
#endif
