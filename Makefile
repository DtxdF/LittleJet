MKDIR?=mkdir -p
INSTALL?=install
SED?=sed -i ''
RM?=rm
PREFIX?=/usr/local
FIND?=find
MANDIR?=${PREFIX}/share/man
MANPAGES=man1/littlejet.1 \
		 man5/littlejet.conf.5

LITTLEJET_VERSION=0.0.2

all: install

install:
	${MKDIR} -m 755 -p "${DESTDIR}${PREFIX}/bin"
	${MKDIR} -m 755 -p "${DESTDIR}${PREFIX}/share"
	${MKDIR} -m 755 -p "${DESTDIR}${PREFIX}/share/littlejet"
	${MKDIR} -m 755 -p "${DESTDIR}${MANDIR}/man1"
	${MKDIR} -m 755 -p "${DESTDIR}${MANDIR}/man5"

	${INSTALL} -m 555 jet.sh "${DESTDIR}${PREFIX}/bin/jet"
	${INSTALL} -m 555 littlejet.sh "${DESTDIR}${PREFIX}/bin/littlejet"

	# files
	${MKDIR} -m 755 -p "${DESTDIR}${PREFIX}/share/littlejet/files"
	${FIND} share/littlejet/files -mindepth 1 -exec ${INSTALL} -m 444 {} "${DESTDIR}${PREFIX}/{}" \;
	
	# RunScripts
	${MKDIR} -m 755 -p "${DESTDIR}${PREFIX}/share/littlejet/runscripts"
	${FIND} share/littlejet/runscripts -mindepth 1 -exec ${INSTALL} -m 555 {} "${DESTDIR}${PREFIX}/{}" \;
	
	# Version
	${SED} -e 's|%%LITTLEJET_VERSION%%|${LITTLEJET_VERSION}|' "${DESTDIR}${PREFIX}/bin/jet"
	
	# man pages
.for manpage in ${MANPAGES}
	${INSTALL} -m 444 share/man/${manpage} "${DESTDIR}${MANDIR}/${manpage}"
.endfor

	# Prefix
.for f in share/littlejet/files/default.conf bin/jet bin/littlejet share/man/man1/littlejet.1 share/man/man5/littlejet.conf.5
	${SED} -i '' -e 's|%%PREFIX%%|${PREFIX}|' "${DESTDIR}${PREFIX}/${f}"
.endfor

uninstall:
	${RM} -f "${DESTDIR}${PREFIX}/bin/jet"
	${RM} -rf "${DESTDIR}${PREFIX}/share/littlejet"
