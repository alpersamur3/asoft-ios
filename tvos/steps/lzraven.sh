# liblzraven (0BSD, a clean-room decoder of Apple's LZRAVEN, which OS 27's OTA payloads (pbzm) use and ipsw cannot
# decode off macOS 27), pinned to commit {COMMIT}: fetched by that commit alone, its checkout checked to be it,
# built, its own test suite run (the correctness gate), then pbzm_dec (this installer's tvos/scripts/pbzm_dec.c)
# linked against it. All in the Linux scratch ($L/liblzraven); a build there of the same commit is kept.
D=$L/liblzraven
C={COMMIT}
if [ -x "$D/pbzm_dec" ] && [ "$(git -C "$D" rev-parse HEAD 2> /dev/null)" = "$C" ] && [ -s "$D/pbzm_dec.c" ] &&
	cmp -s "$D/pbzm_dec.c" "$S/pbzm_dec.c"; then
	echo "have liblzraven $C and pbzm_dec in $D"
	exit 0
fi
N=$D.new
rm -rf "$N"; mkdir -p "$N"
cd "$N"
git init -q
git remote add origin '{REPO}'
# (GitHub serves a commit by its id; --depth 1: that commit only)
git -c protocol.version=2 fetch -q --depth 1 origin "$C"
git checkout -q --detach FETCH_HEAD
got=$(git rev-parse HEAD)
[ "$got" = "$C" ] || { echo "liblzraven's checkout is $got, not the pinned $C"; exit 1; }
[ -z "$(git status --porcelain)" ] || { git status --short | head; echo "liblzraven's checkout is not clean"; exit 1; }
echo "liblzraven $(git log -1 --format='%H %ci')"
make -j"$(nproc)" lib > build.log 2>&1 || { tail -20 build.log; echo "liblzraven did not build"; exit 1; }
make test > test.log 2>&1 || { tail -30 test.log; echo "liblzraven's tests failed: its decoder is not used"; exit 1; }
tail -3 test.log
[ -f build/liblzraven.a ] && [ -f include/lzraven.h ] || { echo "no build/liblzraven.a or include/lzraven.h"; exit 1; }
cp "$S/pbzm_dec.c" pbzm_dec.c
cc -std=c11 -O2 -Wall -Wextra -Iinclude -o pbzm_dec pbzm_dec.c build/liblzraven.a
# (with no arguments it says how it is used and exits 2)
rc=0; ./pbzm_dec > /dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "pbzm_dec does not run (exit $rc)"; exit 1; }
cd /
rm -rf "$D"
mv "$N" "$D"
ls -l "$D/pbzm_dec"
