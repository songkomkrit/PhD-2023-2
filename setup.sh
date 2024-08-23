#!/bin/bash

rootdir=$(pwd)

cd tree-classifiers
mkdir -p images output
cd $rootdir

cd box-classifiers
for dir in */; do
	cd $dir
	mkdir -p log output tmp
	cd ..
done
cd $rootdir
