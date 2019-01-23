---
title: "Сборка пакета с помощью debconf"
date: 2012-08-11T13:14:18+01:00
draft: false
description: сборка .deb пакета с помощью debconf
tags:
  - "*nix"
  - debian
---
Недавно столкнулся с задачей создания .deb пакета. Поскольку информация в сети разбросана и само описание команд debhelper несколько сумбурно, ниже привожу список действий помогающих собрать архив с нуля:

Создание исходников.
 
	#: mkdir package-1.0
	#: echo "Sample file in package" > package-1.0/file
	
Создание специального архива с исходниками

	#: tar czf package-1.0.tar.gz package-1.0/
	#: dh_make -c apache -f ../package-1.0.tar.gz

Редактирование параметров пакета. 

	#: nano debian/control
	
Создание конфигураций:

	#: nano debain/package.templates
	
	Template: package/test
	Type: boolean
	Default: true
	Description: Test boolean property
	  Test boolean property long description
	  
Создание конфига

	#: nano debian/package.config

	#!/bin/bash -e

	. /usr/share/debconf/confmodule

	db_input medium package/test || true
	db_go || true
	
Вызов конфига из postinst скрипта. debhelper не может сгенерировать такой postinst так как "слишком сложно".

	#: mv debian/postinst.ex debian/postinst
	#: nano debian/postinst

	...
	configure)
	. /usr/share/debconf/confmodule
	db_get package/test
	echo "$RET;
	;;
	...
	
Копирование скриптов в некую временную директорию

	#: sudo dh_installdebconf
	#: sudo dh_installdeb
	
Создание пакета

	#: sudo dh_builddeb

	#: cd ../
	
Пакет package_1.0-1_any.deb готов.
Имя пакета package изменить везде выше на необходимое. Например: mycoollapp.
		  