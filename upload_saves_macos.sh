#!/bin/bash

./bin/adb-osx devices | grep device | grep -v List | while read line ; do
	devid=`echo $line | cut -d ' ' -f 1`
	./bin/adb-osx -s $devid shell "run-as com.unofficial.ufo50 mkdir /sdcard/UFO50Backup"
	./bin/adb-osx -s $devid push ./save/save1.ufo /sdcard/UFO50Backup/
	./bin/adb-osx -s $devid push ./save/save2.ufo /sdcard/UFO50Backup/
	./bin/adb-osx -s $devid push ./save/save3.ufo /sdcard/UFO50Backup/
	./bin/adb-osx -s $devid push ./save/account.ufo /sdcard/UFO50Backup/
	./bin/adb-osx -s $devid shell "run-as com.unofficial.ufo50 cp -f /sdcard/UFO50Backup/save1.ufo /data/data/com.unofficial.ufo50/files/"
	./bin/adb-osx -s $devid shell "run-as com.unofficial.ufo50 cp -f /sdcard/UFO50Backup/save2.ufo /data/data/com.unofficial.ufo50/files/"
	./bin/adb-osx -s $devid shell "run-as com.unofficial.ufo50 cp -f /sdcard/UFO50Backup/save3.ufo /data/data/com.unofficial.ufo50/files/"
	./bin/adb-osx -s $devid shell "run-as com.unofficial.ufo50 cp -f /sdcard/UFO50Backup/account.ufo /data/data/com.unofficial.ufo50/files/"
done
