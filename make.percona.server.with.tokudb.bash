#!/bin/bash

function usage() {
    echo "make.percona.server.with.tokudb.bash Percona-Server-5.6.23-72.1 tokudb-7.5.6 [debug|release|debug-valgrind]"
}

# download a github repo as a tarball and expand it in a local directory
# arg 1 is the github repo owner
# arg 2 is the github repo name
# arg 3 is the github commit reference
# the local directory name is the same as the github repo name
function get_repo() {
    local owner=$1; local repo=$2; local ref=$3

    curl -L https://api.github.com/repos/$owner/$repo/tarball/$ref --output $repo.tar.gz
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    mkdir $repo
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    tar --extract --gzip --directory $repo --strip-components 1 --file $repo.tar.gz
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    rm -rf $repo.tar.gz
}

function get_source_from_repos() {
    local buildthype=$1

    # get percona server source
    get_repo $percona_owner percona-server $percona_ref
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    mv percona-server $percona_ref-$buildtype

    if [ ! -f $percona_ref-$buildtype/Docs/INFO_SRC ] ; then
        echo "short: $tokudb_ref" >$percona_ref-$buildtype/Docs/INFO_SRC
    else
        # append the tokudb tag to the revno string
        sed -i -e "1,\$s/\(short:.*\)\$/\1-$tokudb_ref/" $percona_ref-$buildtype/Docs/INFO_SRC
        if [ $? -ne 0 ] ; then test 1 = 0; return ; fi
    fi

    sed -i -e "s/\(PRODUCT_FULL=\"\$PRODUCT_FULL\)/\1-\${REVISION:-}/" $percona_ref-$buildtype/build-ps/build-binary.sh

    # make the tokudb source tarball
    bash -x make.tokudb.source.tarball.bash $perconaserver $tokudb
    if [ $? -ne 0 ] ; then test 1 = 0; return ; fi

    # extract the tokudb source tarball
    tar xzf $percona_ref.tokudb.tar.gz
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi

    # merge
    target=$PWD/$percona_ref-$buildtype
    pushd $percona_ref.tokudb
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    for d in mysql-test storage; do
        if [ -d $d ] ; then
            for f in $(find $d -type f); do
                targetdir=$(dirname $target/$f)
                if [ ! -d $targetdir ] ; then 
                    mkdir -p $targetdir
                    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
                fi
                if [ $(basename $f) = disabled.def ] ; then
                    # append the tokudb disabled.def to the base disabled.def
                    cat $f >>$target/$f
                    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
                else
                    # replace the base file
                    cp $f $target/$f
                    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
                fi
            done
        fi      
    done
    popd

    # get jemalloc
    get_repo jemalloc jemalloc 3.6.0
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    mv jemalloc jemalloc-3.6.0
}

function build_tarballs_from_source() {
    local buildtype=$1
    # build
    jemallocdir=$PWD/jemalloc-3.6.0
    pushd $percona_ref-$buildtype
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    buildargs="--with-jemalloc $jemallocdir"
    if [ $buildtype = "debug" ] ; then buildargs="-d $buildargs"; fi
    if [ $buildtype = "debug-valgrind" ] ; then buildargs="-d -v $buildargs"; fi
    bash -x build-ps/build-binary.sh $buildargs .
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    for x in *.gz; do
        md5sum $x >$x.md5
    done
    popd
}

function make_target() {
    local buildtype=$1
    local builddir=$percona_ref-$tokudb_ref-$buildtype
    rm -rf $builddir
    mkdir $builddir
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    pushd $builddir
    get_source_from_repos $buildtype
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    build_tarballs_from_source $buildtype
    if [ $? -ne 0 ] ; then test 1 = 0; return; fi
    popd
    mv $builddir/$percona_ref-$buildtype/Percona-Server*.gz* .
    # rm -rf build-$buildtype
}

if [ $# -lt 2 ] ; then usage; exit 1; fi
perconaserver=$1
if [[ $perconaserver =~ (.*)/(.*) ]] ; then
    percona_owner=${BASH_REMATCH[1]}
    percona_ref=${BASH_REMATCH[2]}
else
    percona_owner=percona
    percona_ref=$perconaserver
fi
tokudb=$2
if [[ $tokudb =~ (.*)/(.*) ]] ; then
    tokudb_owner=${BASH_REMATCH[1]}
    tokudb_ref=${BASH_REMATCH[2]}
else
    tokudb_owner=tokutek
    tokudb_ref=$tokudb
fi
buildtype=
if [ $# -ge 3 ] ; then buildtype=$3; fi

if [ -z "$buildtype" -o "$buildtype" = release ] ; then make_target release; fi
if [ -z "$buildtype" -o "$buildtype" = debug ] ; then make_target debug; fi
if [ -z "$buildtype" -o "$buildtype" = debug-valgrind ] ; then make_target debug-valgrind; fi
