#include "HakuMachO.h"
#include <stdio.h>
#include <string.h>

static uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
static uint32_t be32(const uint8_t *p) {
    return (uint32_t)p[3] | (uint32_t)p[2]<<8 | (uint32_t)p[1]<<16 | (uint32_t)p[0]<<24;
}
static uint64_t be64(const uint8_t *p) { return (uint64_t)be32(p)<<32 | be32(p+4); }
static int fail(char *error, size_t size, const char *why) {
    if (error && size) snprintf(error, size, "%s", why);
    return 0;
}
static int inside(uint64_t offset, uint64_t size, uint64_t length) {
    return offset <= length && size <= length-offset;
}
static int parse_slice(const uint8_t *all, HakuSlice *s, char *error, size_t error_size) {
    const uint8_t *p = all+s->offset;
    if (s->size < 32 || le32(p) != 0xfeedfacf)
        return fail(error,error_size,"Only little-endian 64-bit Mach-O slices are supported");
    s->cpu_type=le32(p+4); s->cpu_subtype=le32(p+8);
    uint32_t count=le32(p+16), commands_size=le32(p+20);
    if (!inside(32,commands_size,s->size) || count>commands_size/8)
        return fail(error,error_size,"Invalid load-command table");
    uint64_t at=32, end=32+(uint64_t)commands_size;
    for (uint32_t i=0;i<count;i++) {
        if (!inside(at,8,end)) return fail(error,error_size,"Truncated load command");
        uint32_t cmd=le32(p+at), size=le32(p+at+4);
        if (size<8 || size%4 || !inside(at,size,end))
            return fail(error,error_size,"Invalid load-command size");
        if (cmd==0x1b) {
            if (size<24 || s->has_uuid) return fail(error,error_size,"Invalid or duplicate UUID");
            memcpy(s->uuid,p+at+8,16); s->has_uuid=1;
        } else if (cmd==0x21 || cmd==0x2c) {
            if (size<(cmd==0x2c?24:20) || s->range_count==HAKU_MAX_RANGES)
                return fail(error,error_size,"Invalid encryption command");
            HakuCryptRange *r=&s->ranges[s->range_count++];
            r->offset=le32(p+at+8); r->size=le32(p+at+12);
            r->cryptid=le32(p+at+16); r->cryptid_offset=at+16;
            if (!inside(r->offset,r->size,s->size) || (r->size && r->offset<end))
                return fail(error,error_size,"Encryption range outside slice or overlaps commands");
            for (unsigned j=0;j+1<s->range_count;j++) {
                HakuCryptRange *previous=&s->ranges[j];
                if (r->size && previous->size && r->offset<previous->offset+previous->size && previous->offset<r->offset+r->size)
                    return fail(error,error_size,"Overlapping encryption ranges");
            }
        }
        at+=size;
    }
    if (at!=end) return fail(error,error_size,"Load-command size does not match table");
    return 1;
}
int haku_parse_macho(const void *bytes, size_t length, HakuMachO *result, char *error, size_t error_size) {
    memset(result,0,sizeof(*result));
    if (!bytes || length<4) return fail(error,error_size,"Truncated Mach-O");
    const uint8_t *p=bytes;
    uint32_t magic=be32(p);
    if (magic==0xcafebabe || magic==0xcafebabf) {
        if (length<8) return fail(error,error_size,"Truncated FAT header");
        unsigned count=be32(p+4), stride=magic==0xcafebabf?32:20;
        if (!count || count>HAKU_MAX_SLICES || !inside(8,(uint64_t)count*stride,length))
            return fail(error,error_size,"Invalid FAT slice table");
        result->count=count;
        for (unsigned i=0;i<count;i++) {
            const uint8_t *a=p+8+i*stride;
            HakuSlice *s=&result->slices[i];
            s->offset=stride==32?be64(a+8):be32(a+8);
            s->size=stride==32?be64(a+16):be32(a+12);
            if (s->offset<8+(uint64_t)count*stride || !inside(s->offset,s->size,length))
                return fail(error,error_size,"FAT slice outside file");
            for (unsigned j=0;j<i;j++) {
                HakuSlice *prev=&result->slices[j];
                if (s->offset<prev->offset+prev->size && prev->offset<s->offset+s->size)
                    return fail(error,error_size,"Overlapping FAT slices");
            }
            if (!parse_slice(p,s,error,error_size)) return 0;
            if (s->cpu_type!=be32(a) || s->cpu_subtype!=be32(a+4))
                return fail(error,error_size,"FAT architecture identity mismatch");
        }
    } else {
        result->count=1; result->slices[0].size=length;
        if (!parse_slice(p,&result->slices[0],error,error_size)) return 0;
    }
    return 1;
}
void haku_uuid_string(const uint8_t uuid[16], char output[33]) {
    for (int i=0;i<16;i++) snprintf(output+i*2,3,"%02x",uuid[i]);
}
int haku_validate_transition(const void *original, const void *derived, size_t length, char *error, size_t error_size) {
    HakuMachO a,b;
    if (!haku_parse_macho(original,length,&a,error,error_size) || !haku_parse_macho(derived,length,&b,error,error_size)) return 0;
    if (a.count!=b.count) return fail(error,error_size,"Slice inventory changed");
    const uint8_t *x=original,*y=derived;
    struct { uint64_t start,end; } allowed[HAKU_MAX_SLICES*HAKU_MAX_RANGES*2];
    unsigned intervals=0;
    for (unsigned i=0;i<a.count;i++) {
        HakuSlice *s=&a.slices[i],*t=&b.slices[i];
        if (s->offset!=t->offset || s->size!=t->size || s->cpu_type!=t->cpu_type || s->cpu_subtype!=t->cpu_subtype || s->has_uuid!=t->has_uuid || memcmp(s->uuid,t->uuid,16) || s->range_count!=t->range_count)
            return fail(error,error_size,"Mach-O identity changed");
        for (unsigned j=0;j<s->range_count;j++) {
            HakuCryptRange *r=&s->ranges[j],*q=&t->ranges[j];
            if (r->offset!=q->offset || r->size!=q->size || r->cryptid_offset!=q->cryptid_offset)
                return fail(error,error_size,"Encryption layout changed");
            if (!r->cryptid || !r->size) {
                if (r->cryptid!=q->cryptid) return fail(error,error_size,"Originally clear range was modified");
                continue;
            }
            if (!s->has_uuid) return fail(error,error_size,"Encrypted slice has no UUID");
            if (q->cryptid!=0) return fail(error,error_size,"Encrypted command remains");
            if (!memcmp(x+s->offset+r->offset,y+s->offset+r->offset,(size_t)r->size))
                return fail(error,error_size,"Encryption-range bytes did not change");
            allowed[intervals].start=s->offset+r->offset;
            allowed[intervals++].end=s->offset+r->offset+r->size;
            allowed[intervals].start=s->offset+r->cryptid_offset;
            allowed[intervals++].end=s->offset+r->cryptid_offset+4;
        }
    }
    for (unsigned i=0;i<intervals;i++) for (unsigned j=i+1;j<intervals;j++) {
        if (allowed[j].start<allowed[i].start) {
            uint64_t start=allowed[i].start,end=allowed[i].end;
            allowed[i]=allowed[j]; allowed[j].start=start; allowed[j].end=end;
        }
    }
    uint64_t cursor=0;
    for (unsigned i=0;i<intervals;i++) {
        if (allowed[i].start<cursor) return fail(error,error_size,"Overlapping transition allowances");
        if (memcmp(x+cursor,y+cursor,(size_t)(allowed[i].start-cursor)))
            return fail(error,error_size,"Stable bytes changed outside encryption range");
        cursor=allowed[i].end;
    }
    if (memcmp(x+cursor,y+cursor,length-(size_t)cursor))
        return fail(error,error_size,"Stable bytes changed outside encryption range");
    return 1;
}
