---
title: "Дистрибьюция Java приложений"
date: 2015-08-18T13:55:18+01:00
draft: false
cover: /img/java-dist/75bbd9f6074d4cb8a46ad705051aa8e0.png
tags:
  - java
  - ubuntu
  - deb
  - администрирование
  - s3
  - maven
---
![](/img/java-dist/75bbd9f6074d4cb8a46ad705051aa8e0.png)

Удивительно, но факт - дистрибьюция Java приложений в 21 веке по прежнему огромный костыль. Разработчики до сих пор придумывают способы вроде rsync/copy-paste/wget для установки java приложений на сервер. И только монструозные enterprise production ready платформы иногда позволяют сделать чуть больше - откатить приложение на предыдущую версию. В этой статье я хотел бы рассказать о доступном и простом способе организации дистрибьюции.

deb и apt
---------

В мире существует множество действительно гигантских репозиториев приложений и инструментов по их дистрибьюции. Самые большие, по ощущениям, - это AppStore, Google Play, Debian/Ubuntu репозитории и CentOS/Fedora YUM репозитории. Например в Ubuntu репозитории для версии 15.04 содержится около 90000 приложений (без учета различных версий). Почему бы не воспользоваться провернной временем системой и для дистрибьюции Java приложений? Тем более, что:

- [большинство](http://w3techs.com/technologies/details/os-linux/all/all) серверов и так используют Debian/Ubuntu
- проверенный временем инструмент: первый релиз был [16 лет](https://en.wikipedia.org/wiki/Advanced_Packaging_Tool) назад
- нативная поддержка в операционной системе

Для начала немного о системе дистрибьюции приложений в Debian/Ubuntu. Она состоит из двух основных частей:

- deb пакеты
- apt (Advanced Package Tool) инструменты

deb пакеты
----------

deb это бинарный дистрибутив приложения. Он состоит из 3 основных частей:

- метаинформация. Производитель, версия, зависимости на другие пакеты (очень похоже на maven), описание и пр.
- непосредственно приложение. .tar.gz архив
- (опционально) скрипты, которые будут выполняться во время установки

Структура .tar.gz архива может быть абсолютно произвольной. Однако, чтобы Ваше приложение было похоже на все остальные приложения системы, оно должно следовать структуре каталогов Debian/Ubuntu:

- /etc - конфиги
- /etc/init.d/ - скрипты запуска демонов
- /usr/bin - исполняемые файлы
- /usr/lib - библиотеки
- /var/log - логи

В зависимости от Вашего приложения каталоги могут немного отличаться, но общая структура надеюсь понятна.

Еще одной важной особенностью deb пакетов является возможность запускать скрипты во время установки. Эти скрипты тоже хранятся в deb пакете и имеют стандартное именование. Каждый скрипт может выполняться в определенную фазу установки. Установка пакета делится на несколько фаз:

- preinst
- inst
- postinst
- prerm
- rm
- postrm

Существует множество различных промежуточных фаз и различные комбинации состояния инсталляции. Нас они мало интересуют, но тем кто хочет разобраться можно почитать <a href="https://www.debian.org/doc/debian-policy/ch-maintainerscripts.html">официальную документацию</a>. Обычно эти скрипты настраивают ротацию и архивирование логов, задают начальные значения конфигураций (например, root-пароль для mysql). Если же у вас конечное бизнес-приложение, то лучше взять какое-нибудь нормальное средство автоматизации вроде <a href="http://www.ansible.com/home">Ansible</a>, <a href="https://www.chef.io/chef/">Chief</a>, <a href="https://puppetlabs.com">Puppet</a>.

apt
------

apt - это набор инструментов для работы с deb пакетами. Он позволяет:

- конфигурировать репозитории и работать с ними: добавлять, удалять, менять, обновлять индекс
- управлять пакетами: устанавливать, удалять, обновлять, искать

apt репозиторий в упрощенном виде - это HTTP сервер, который раздает deb пакеты. У него есть индекс (файл), который доступен по стандартному пути и непосредственно бинарники, путь к которым находится в индексе.

Связывая все воедино
-------------------

После того, как стала понятна примерная схема работы связки deb + apt, можно попробовать их съинтегрировать. Примерная схема такая:

- создания deb пакета в фазе package
- публикация получившегося пакета в фазе deploy

Для этого есть несколько maven плагинов.

<a href="https://github.com/tcurdt/jdeb">jdeb</a>
-------------------------------------------------

Схема его работы достаточно <a href="https://github.com/tcurdt/jdeb/blob/master/src/examples/maven/pom.xml">проста</a>:

- перечислить файлы и директории, которые попадут в результирующий .tar.gz архив
- указать пермиссии

Более полная документация о возможностях плагина можно узнать на официальной <a href="https://github.com/tcurdt/jdeb/blob/master/docs/maven.md">странице</a>.

<a href="https://github.com/dernasherbrezon/apt-maven-plugin">apt-maven-plugin</a>
----------------------------------

Работает с репозиторием заданным в distributionManagement как с apt репозиторием, а не maven репозиторием. Хотя ничего не мешает их использовать одновременно под одним url. Их layout'ы совместимы между собой.

Пример конфигурации выглядит следующим образом:

```xml
<plugin>
	<groupId>com.aerse.maven</groupId>
	<artifactId>apt-maven-plugin</artifactId>
	<version>1.5</version>
	<executions>
		<execution>
			<id>deploy</id>
			<goals>
				<goal>deploy</goal>
			</goals>
		</execution>
	</executions>
	<configuration>
		<component>main</component>
		<codename>strepo</codename>
	</configuration>
</plugin>
```
	
И секция distributionManagement (ничего <a href="https://maven.apache.org/plugins/maven-deploy-plugin/usage.html">необычного</a>):

```xml
<distributionManagement>
	<repository>
		<id>maven-release-repo</id>
		<url>http://example.com/maven</url>
	</repository>
</distributionManagement>
```

После выполнения фазы deploy, http://example.com/maven станет еще и apt репозиторием. И можно смело писать:

```bash
sudo add-apt-repository "deb http://example.com/maven strepo main"
sudo apt-get update
sudo apt-get install <artifactId>
```

Немного любимого enterprise
--------------------------

Манца любого java-enterprise разработчика звучит следующим образом:

- security
- stability
- high availability production ready platform

Все это отлично решается, если устроить apt репозиторий из самого популярного хостинга для разработчиков: <a href="https://aws.amazon.com/s3/">s3</a>. Вкупе с cloudfront, он даёт гарантию <a href="https://aws.amazon.com/s3/sla/">99.9%</a> надёжности и географическую <a href="https://www.google.com/maps/d/viewer?mid=zq41xmfbtRfA.kUKJZcl-4O7k&hl=en">распределённость</a>.

Делается это опять же достаточно просто. Надо подключить плагин для работы с s3:

```xml
<build>
	<extensions>
		<extension>
			<groupId>org.springframework.build</groupId>
			<artifactId>aws-maven</artifactId>
			<version>5.0.0.RELEASE</version>
		</extension>
	</extensions>
</build>
```

Поменять url в секции distributionManagement на имя bucket'a:

```xml
<distributionManagement>
	<repository>
		<id>maven-release-repo</id>
		<url>s3://example.bucket</url>
	</repository>
</distributionManagement>
```

И настроить доступ к вашему bucket'у:

```xml
<servers>
	<server>  
		<id>maven-release-repo</id>  
		<username>apikey</username>  
		<password>apisecret</password>  
	</server>
</servers>
```

На конечных серверах для доступа к такому репозиторию существует специальный плагин: <a href="https://launchpad.net/~leonard-ehrenfried/+archive/ubuntu/apt-transport-s3">apt-transport-s3</a>. К сожалению его еще нет в официальных репозиториях, поэтому необходимо добавить вручную один из репозиториев, где он содержится:

```bash
sudo add-apt-repository ppa:leonard-ehrenfried/apt-transport-s3
sudo apt-get install apt-transport-s3
```

После чего можно уже указывать наш s3 репозиторий:

```bash
sudo add-apt-repository "deb s3://apikey:apisecret@s3.amazonaws.com/example.bucket strepo main"
```

Итого
------------

В результате всех манипуляций установка приложения:

- mvn clean deploy

На любом Debian/Ubuntu сервере в любой точке мира:

- apt-get update
- apt-get install artifactId