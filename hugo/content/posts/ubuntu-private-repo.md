---
title: "Приватный репозиторий в Ubuntu"
date: 2018-06-07T10:07:18+01:00
draft: false
tags:
  - java
  - ubuntu
  - openstack
  - valgrind
  - maven
  - selectel
  - openstack swift
  - c
  - apt
---
В Ubuntu репозитории – это специальные сервера-хранилища для приложений. Если Вы разрабатываете коммерческое приложение и запускаете его в Ubuntu, то логично положить его в репозиторий. А потом управлять этим приложением так же, как и обычными системными приложениями. Для этого нужно поднять в локальной сети или облаке apache, настроить логин и пароль, не забывать его обновлять...Но что если есть другой способ?

Облачные хранилища
------------------

С помощью [apt-transport-s3](https://packages.debian.org/sid/apt-transport-s3) можно превратить bucket в приватный apt репозиторий. Однако, у этого способа появились следующие недостатки:
- Некоторые адреса Амазона заблокированы в России
- Данные находятся в Европе, поэтому может быть медленно.

Какие же есть альтернативы?

Самой известной считается [Openstack Swift](https://docs.openstack.org/swift/latest/). Swift (OpenStack Object Storage) — это полностью распределенное «безграничное» хранилище, которое характеризуется отказоустойчивостью и высокой надежностью. Создано как конкурент Amazon S3. Его преимущества:
- В России как минимум 2 провайдера предоставляют Swift как сервис: [Clodo](http://lib.clodo.ru/cloud-storage/cloudstorage.html) и [Selectel](https://selectel.ru/services/cloud/storage/)
- Данные находятся в России
- Если Вы достаточно большие, то можете поднять его у себя
- Все плюсы облачного хранилища: оплата за непосредственно используемые ресурсы, распределенное хранение, отказоустойчивость, 24/7.

Из недостатков можно выделить лишь полное отсутствие интеграции с Ubuntu. Это сложно назвать недостатком, если Вы программист. Поэтому я написал интеграцию сам: [apt-transport-swift](https://github.com/dernasherbrezon/apt-transport-swift).

Разработка 
===============

Для начала нужно немного погрузиться в то, как apt взаимодействует в репозиториями. Для того, чтобы получить информацию из репозитория, apt:
- находит соответствующий метод из списка установленных. Все они лежат в папке: /usr/lib/apt/methods/
- отправляет ему необходимые команды согласно протоколу

По умолчанию доступно достаточно много методов: http, ftp, cdrom, file, ssh и тд. Все они работают следующим образом:
- каждый метод - это отдельная программа
- на вход apt отправляет через stdin команды для выполнения
- на выходе через stdout метод должен вернуть результат работы

Команды и ответы передаются в текстовом виде очень похожим на http. Например:

```
100 Capabilities
Version: 1.2
Pipeline: true
Send-Config: true
```

Эту команду отправляет метод, чтобы получить конфигурацию apt.conf:

```
600 URI Acquire
URI: swift://container/dists/stretch/InRelease
Filename: dists_stretch_InRelease
Expected-SHA1: 123
Last-Modified: Wed, 23 May 2018 14:13:16 GMT
```

Эту команду отправляет apt, когда необходимо скачать файл. Когда метод закончил скачивание, он возвращает:

```
201 URI Done
URI: swift://container/dists/stretch/InRelease
Filename: dists_stretch_InRelease
Expected-SHA1: 123
Size: 762361
Last-Modified: Wed, 23 May 2018 14:13:16 GMT
```

Поскольку все методы написаны на C++, я решил тоже написать на C++. После двух недель, мои глаза стали вытекать и я решил начать с чего-нибудь попроще. С. Программа вылядела достаточно простой, но результат не удовлетворял моих высоких стандартов качества. Еще две недели пришлось потратить на изучение утечек памяти, инструментов тестирования и настройки билда в [Travis](https://travis-ci.org/dernasherbrezon/apt-transport-swift).

Всё вместе
================

В результате я получил следующую схему для Java проектов:

![](xxiubje3ios6bvc16lre6dl-vlq.png)

1. Сброка .deb артефакта с помощью [deb-maven-plugin](https://github.com/dernasherbrezon/deb-maven-plugin). pom.xml:
```xml
<plugins>
...
	<plugin>
		<groupId>com.aerse.maven</groupId>
		<artifactId>deb-maven-plugin</artifactId>
		<version>1.4</version>
		<executions>
			<execution>
				<id>package</id>
				<phase>package</phase>
				<goals>
					<goal>package</goal>
				</goals>
			</execution>
		</executions>
		<configuration>
			<unixUserId>ubuntu</unixUserId>
			<unixGroupId>ubuntu</unixGroupId>
			<osDependencies>
				<openjdk-7-jdk></openjdk-7-jdk>
				<nginx></nginx>
			</osDependencies>
			<javaServiceWrapper>true</javaServiceWrapper>
			<fileSets>
				<fileSet>
					\<source>${basedir}/src/main/deb</source>
					<target>/</target>
				</fileSet>
			</fileSets>
		</configuration>
	</plugin>
...
</plugins>
```

2. Дистрибьюция артефакта в apt репозиторий. [Плагин](https://github.com/dernasherbrezon/apt-maven-plugin) проинициализирует репозиторий, если он изначально пустой. pom.xml:
```xml
<plugins>
...
  <plugin>
    <groupId>com.aerse.maven</groupId>
    <artifactId>apt-maven-plugin</artifactId>
    <version>1.9</version>
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
		<codename>myrepo</codename>
		<sign>true</sign>
		<keyname>name</keyname>
		<passphraseServerId>gpg.passphrase</passphraseServerId>
	</configuration>
  </plugin>
...
</plugins>
```
settings.xml:
```xml
<settings>
  ...
  <servers>
    ...
    <server>
      <id>gpg.passphrase</id>
      <passphrase>passphrase</passphrase>
    </server>
    ...
  </servers>
  ...
</settings>
```

3. В maven есть такое понятие как wagon. Это особая точка расширения, позволяющая добавить новый протокол. С помощью [swift-maven](https://github.com/dernasherbrezon/swift-maven) я добавил поддержку протокола swift. pom.xml:

```xml
<project>
  ...
  <distributionManagement>
    <repository>
      <id>private-repo</id>
      <url>swift://api.selcdn.ru/v3</url>
    </repository>
  </distributionManagement>
  ...

  <build>
    ...
    <extensions>
      ...
      <extension>
        <groupId>com.aerse</groupId>
        <artifactId>swift-maven</artifactId>
        <version>1.1</version>
      </extension>
      ...
    </extensions>
    ...
  </build>  
</project>
```
settings.xml:
```xml
<settings>
  ...
  <servers>
    ...
    <server>
      <id>private-repo</id>
      <username>username</username>
      <password>password</password>
    </server>
    ...
  </servers>
  ...
</settings>
```

4. В качестве облачного хранения данных я выбрал [Selectel](https://selectel.com/?ref_code=9AMKYUS5Md3m). Они поддерживают API Swift v3.
5. [apt-transport-swift](https://github.com/dernasherbrezon/apt-transport-swift) реализует swift протокол для apt.

```
#: cat /etc/apt/sources.list.d/privaterepo.list

deb swift://container myrepo main
```
И конфигурация:

```
#: cat /etc/apt/apt.conf.d/80privaterepo

Swift {
 Container0 {
   Name "container";
   URL "https://api.selcdn.ru";
   Username "username";
   Password "password";
 };
};
```

Результат
========

Хочется отметить, что схема не добавляет никаких новых сущностей в уже существующие инструменты. Всё реализовано в виде плагинов и должно работать независимо друг от друга. Например, с помощью [apt-maven-plugin](https://github.com/dernasherbrezon/apt-maven-plugin) можно деплоить в S3.
