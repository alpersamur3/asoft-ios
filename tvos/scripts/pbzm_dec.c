/* pbzm_dec FILE OFFSET LENGTH: decode one pbzm (or pbzx-stored) container that sits at
 * FILE[OFFSET, OFFSET+LENGTH) and write the decoded bytes to stdout.
 * Every block must decode to exactly its declared unc_size; the walk must end exactly at LENGTH.
 * On success prints "OK blocks=N lzraven=N stored=N out=BYTES" to stderr and exits 0. */
#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lzraven.h"

static uint64_t be64(const uint8_t *p)
{
	uint64_t v = 0;
	for (int i = 0; i < 8; i++)
		v = v << 8 | p[i];
	return v;
}

static int rd(int fd, void *buf, size_t n, uint64_t off)
{
	size_t got = 0;
	while (got < n) {
		ssize_t r = pread(fd, (uint8_t *)buf + got, n - got, (off_t)(off + got));
		if (r < 0 && errno == EINTR)
			continue;
		if (r <= 0)
			return -1;
		got += (size_t)r;
	}
	return 0;
}

static int wr(const uint8_t *p, size_t n)
{
	while (n) {
		ssize_t w = write(1, p, n);
		if (w < 0 && errno == EINTR)
			continue;
		if (w <= 0)
			return -1;
		p += w;
		n -= (size_t)w;
	}
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 4) {
		fprintf(stderr, "usage: %s FILE OFFSET LENGTH\n", argv[0]);
		return 2;
	}
	int fd = open(argv[1], O_RDONLY);
	if (fd < 0) {
		perror(argv[1]);
		return 2;
	}
	uint64_t base = strtoull(argv[2], NULL, 0), len = strtoull(argv[3], NULL, 0);
	uint8_t h[16];
	if (len < 12 || rd(fd, h, 12, base)) {
		fprintf(stderr, "short header\n");
		return 1;
	}
	if (memcmp(h, "pbzm", 4) && memcmp(h, "pbzx", 4)) {
		fprintf(stderr, "bad magic %.4s\n", (char *)h);
		return 1;
	}
	size_t ccap = 0, ucap = 0;
	uint8_t *cbuf = NULL, *ubuf = NULL;
	uint64_t off = 12, out = 0, nblk = 0, nrav = 0, nraw = 0;
	while (off < len) {
		if (len - off < 16 || rd(fd, h, 16, base + off)) {
			fprintf(stderr, "truncated block header at %llu\n", (unsigned long long)off);
			return 1;
		}
		uint64_t unc = be64(h), comp = be64(h + 8);
		off += 16;
		if (comp > len - off || unc > (1u << 30)) {
			fprintf(stderr, "block %llu: bad sizes unc=%llu comp=%llu\n",
				(unsigned long long)nblk, (unsigned long long)unc, (unsigned long long)comp);
			return 1;
		}
		if (comp > ccap) {
			free(cbuf);
			ccap = comp;
			cbuf = malloc(ccap);
		}
		if (unc + 1 > ucap) {
			free(ubuf);
			ucap = unc + 1;
			ubuf = malloc(ucap);
		}
		if (!cbuf || !ubuf || rd(fd, cbuf, comp, base + off)) {
			fprintf(stderr, "block %llu: read/alloc failed\n", (unsigned long long)nblk);
			return 1;
		}
		const uint8_t *res;
		if (comp >= 4 && !memcmp(cbuf, "\x2b\x00\xca\xec", 4)) {
			lzraven_status st;
			size_t n = lzraven_decode_buffer_ex(ubuf, unc, cbuf, comp, &st);
			if (st != LZRAVEN_OK || n != unc) {
				fprintf(stderr, "block %llu: decode %s, got %zu want %llu\n",
					(unsigned long long)nblk, lzraven_status_string(st), n,
					(unsigned long long)unc);
				return 1;
			}
			res = ubuf;
			nrav++;
		} else if (comp == unc) {
			res = cbuf;
			nraw++;
		} else {
			fprintf(stderr, "block %llu: unknown codec (comp %llu != unc %llu, no raven magic)\n",
				(unsigned long long)nblk, (unsigned long long)comp, (unsigned long long)unc);
			return 1;
		}
		if (wr(res, unc)) {
			fprintf(stderr, "write failed\n");
			return 1;
		}
		out += unc;
		off += comp;
		nblk++;
	}
	fprintf(stderr, "OK blocks=%llu lzraven=%llu stored=%llu out=%llu\n", (unsigned long long)nblk,
		(unsigned long long)nrav, (unsigned long long)nraw, (unsigned long long)out);
	return 0;
}
