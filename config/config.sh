#!/bin/bash

# Intel version 14
if [[ -d /usr/local/intel_14 ]]; then
  source /usr/local/intel_14/bin/compilervars.sh intel64 &> /dev/null
fi

# madagascar
export DATAPATH=${HOME}/.rsfdata/
export PYTHONPATH=$PYTHONPATH:$RSFSRC/build/book/Recipes

# cuda
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# SEPLIB
export SEP=/data/bob/SEP
newPATH87=${SEP:?'required environment variable SEP missing'}/bin:${PATH}
if [ ! -d ${SEP} ] ; then
  echo "${SEP} is not a directory. Exiting ..."
else
  PATH="${newPATH87}"
  export PATH
  SEPINC=${SEP}/include
  export SEPINC
  myld=""
  if [ ] ; then
    mytmp=/tmp/${USER}_junk$$
    ( for i in `/sbin/ldconfig -p | grep '=>' | awk '{ print $NF }'` ; do dirname $i ; done ) | sort -r | uniq > ${mytmp}
    for j in `cat ${mytmp}` ; do myld=${j}:${myld} ; done
    rm -f ${mytmp}
  fi
  LD_LIBRARY_PATH=${myld}${LD_LIBRARY_PATH}:${SEP}/lib:${SEP}/lib/syslibs
  export LD_LIBRARY_PATH
  MANPATH=${SEP}/man:${MANPATH}
  export MANPATH
  LANG=${LANG:-'C'}
  export LANG
fi
unset newPATH87