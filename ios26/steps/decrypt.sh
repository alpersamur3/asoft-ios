mkdir -p os
for i in {SYSOS} {OS}; do
	if [ -f "iphone/$i.aea" ]; then
		rm -f "os/${i:?}"
	elif [ ! -s "os/$i" ]; then
		echo "neither iphone/$i.aea nor os/$i: run Install-iOS26.cmd -From iphone"
		exit 1
	fi
done
if [ -f iphone/{SYSOS}.aea ]; then bash $S/sysos.sh; fi
if [ -f iphone/{OS}.aea ]; then bash $S/m2-decrypt.sh; fi
ls -l os/{SYSOS} os/{OS}
