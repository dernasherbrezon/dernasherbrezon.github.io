---
title: "BLE сервер на Java"
date: 2023-01-17T08:22:17+01:00
draft: false
tags:
  - java
  - bluetooth
  - r2cloud
---
В одном из [предыдущих постов]({{< ref "/lora-deep-sleep" >}}) я начал оптимизировать энергопотребление ESP32 и LoRa. Идея заключалась в том, чтобы переводить микроконтроллер в режим сна и просыпаться только тогда, когда необходимо получить данные. Но как узнать в какой момент времени нужно просыпаться? Вот тут всё зависит от конкретного приложения. Если необходимо передавать данные с одинаковым интервалом, то его можно захардкодить в прошивке. А что делать, если получение данных нужно делать через заранее неизвестные промежутки времени? В моём проекте [r2cloud](https://github.com/dernasherbrezon/r2cloud) как раз такой случай.

## Схема работы

r2cloud составляет расписание пролёта спутников в зависимости от разных параметров. Как только спутник оказывается в области видимости, начинается приём данных. Как только спутник улетел за горизонт, сигнал обрабатывается и отправляется на сервер.

ESP32 должен получать с сервера время начала следующего наблюдения и засыпать. По пробуждению нужно ещё раз получить параметры и начать принимать сигнал. Проще всего описать алгоритм работы с помощью диаграммы последовательности:

{{< svg "/img/ble-server-java/2.svg" >}}

На этой диаграмме минимизирована коммуникация между ESP32 и r2cloud для экономии энергии. Также микроконтроллер выступает активным компонентом, который инициирует все взаимодействия. Это решает проблему polling данных, всевозможных таймаутов и прочего.

Осталось понять каким образом ESP32 должен получать данные с сервера. Тут есть несколько вариантов:

 * По проводу через serial интерфейс. Однако, это сводит на нет, весь смысл глубокого сна и экономии энергии. Ведь по проводу можно передать и питание.
 * LoRa. Выглядит очень заманчиво. ESP32 получает данные со спутника и ретранслирует дальше. [LoRa модуль на RaspberryPI]({{< ref "/lora-raspberrypi" >}}) получает данные и передаёт в r2cloud. Но для этого нужно покупать отдельный LoRa модуль, паять и настраивать. Всё это значительно усложняет систему.
 * Bluetooth. Он есть и на ESP32 и на RaspberryPI.
 * Wi-Fi. Для того, чтобы отправить небольшое сообщение, нужно подсоединится к точке доступа, зашифровать данные и отправить. Мало того, что это потребляет много энергии, так ещё и нужна отдельная точка доступа.
 
Я решил разобраться с Bluetooth и посмотреть, что получится.

## BLE

BLE (Bluetooth Low Energy) - это беспроводная технология Bluetooth с низким энергопотреблением. Её основная идея заключается в том, что два устройства не должны постоянно держать соединение активным, тем самым потребляя энергию. Вместо этого есть набор специальных "профилей" - GAP и GATT, которые предоставляют программную модель для отправки коротких сообщений между двумя устройствами. При этом с точки зрения программиста выглядит будто бы два устройства соединены и активны.

Каждое устройство, которое хочет предоставить доступ к своим возможностям через BLE, должно создать в памяти древовидную структуру свойств, методов и сервисов. Эта структура определена в спецификации GATT (Generic Attribute Profile).

{{< svg "/img/ble-server-java/3.svg" >}}

Для примера, я подключился к своим часам с помощью программы [nRF Connect](https://www.nordicsemi.com/Products/Development-tools/nrf-connect-for-desktop):

![](/img/ble-server-java/1.png)

Справа видна часть публичной информации, которую публикует устройство:

 * Сервис "Device information"
   * Характеристика "Model Number String"
   * Характеристика "Manufacturer Name String"

Для того, чтобы LoRa смогла отправить данные на RaspberryPI нужно будет создать похожую структуру. И вот тут начинаются некоторые сложности, так как в разных операционных системах разные API и подходы.

## Bluez

Для работы с Bluetooth в Linux используется целый стек под названием [bluez](https://github.com/bluez/bluez). Стек в данном случае подразумевает набор драйверов для Linux и реализаций разных Bluetooth профилей, которые могут работать на разных уровнях модели OSI. Сюда так же входят различные программы для управления bluetooth такие как hcitool или gatttool.

В моём случае наиболее интересные профили bluez - это GAP и GATT. Первый - это легковесный протокол обнаружения устройств, а второй - способ организации объектов и полей в дерево.

bluez позволяет управлять устройством с помощью интерфейсов и объектов D-Bus.

## D-Bus

D-Bus - это система междпроцессорного взаимодействия в Linux. Она представляет собой что-то вроде центральной шины, через которую приложения могут посылать друг другу сигналы, вызывать методы и получать свойства. 

![](/img/ble-server-java/4.png)

bluez создаёт в D-Bus дерево объектов и свойств для каждого подключённого устройства. И уже работая с этими объектами, можно получать или отправлять данные на устройства. Немножко запутанно, но этот подход позволяет подключать несколько разных bluetooth устройств к одному физическому bluetooth чипу и независимо работать с каждым из них.

На скриншоте вверху видно, что bluez создал D-Bus объект ```org.bluez.Device1``` для подключённого устройства ```78:DD:08:A3:A7:52```. Это устройство предоставляет доступ к нескольким сервисам и их свойствам:

 * service0001
   * characteristic0006
 * service0010
   * characteristic0012
 * service0100
 * service0200
   * characteristic0204
   * characteristic0212
 * service0680
 
В данном примере удалённое устройство предоставляет доступ к своим сервисам. А что если нужно сделать наоборот: выставить наружу доступ к RaspberryPI? Для этого нужно написать приложение, которое зарегистрирует в bluez необходимые сервисы.

## GATT сервер

В общем случае схема выглядит так:

{{< svg "/img/ble-server-java/5.svg" >}}

Приложение должно создать в D-Bus структуру сервисов и их свойств:

 * Сервисы должны реализовывать интерфейс ```org.bluez.GattService1```
 * Свойства должны реализовывать интерфейс ```org.bluez.GattCharacteristic1```
 
Несмотря на то, что названия интерфейсов очень похожи на нормальные Java объекты, они не имеют ничего общего с Java. Это просто строчка из спецификации bluez.

После того, как объекты созданы, нужно найти объект Service Manager в D-Bus и зарегистрировать в нём приложение. Service Manager - это D-Bus объект, реализующий интерфейс ```org.bluez.GattManager1```.

Далее необходимо каким-то образом рассказать всем устройствам в округе какие сервисы поддерживает RaspberryPI. Для этого нужно:

 * В D-Bus создать объект типа ```org.bluez.LEAdvertisement1```, в котором будет список сервисов, доступных для внешних устройств
 * Зарегистрировать этот объект в Advertising Manager
 
## Интеграция с Java

Итак, в результате задача свелась к тому, чтобы подключиться к D-Bus и зарегистрировать нужные сервисы. По-умолчанию к D-Bus можно подключиться только через [unix domain socket (UDS)](https://ru.wikipedia.org/wiki/Сокет_домена_Unix): ```/var/run/dbus/system_bus_socket```. В Java поддержка UDS появилась только в версии 16. Работа с ними очень похожа на обычные сокеты:

```java
ServerSocketChannel serverChannel = ServerSocketChannel
  .open(StandardProtocolFamily.UNIX);
serverChannel.bind(socketAddress);
SocketChannel channel = serverChannel.accept();
while (true) {
    readSocketMessage(channel)
      .ifPresent(message -> System.out.printf("[Client message] %s", message));
    Thread.sleep(100);
}
```

Но лучше всего воспользоваться готовыми библиотеками от [hypfvieh](https://github.com/hypfvieh). Они абстрагируют работу с dbus и предоставляют нужные API для работы с bluez:

```xml
<dependency>
	<groupId>com.github.hypfvieh</groupId>
	<artifactId>bluez-dbus</artifactId>
	<version>0.1.4</version>
	<exclusions>
		<exclusion>
			<groupId>com.github.hypfvieh</groupId>
			<artifactId>dbus-java</artifactId>
		</exclusion>
	</exclusions>
</dependency>
<dependency>
	<groupId>com.github.hypfvieh</groupId>
	<artifactId>dbus-java-core</artifactId>
	<version>4.2.1</version>
</dependency>
<dependency>
	<groupId>com.github.hypfvieh</groupId>
	<artifactId>dbus-java-transport-native-unixsocket</artifactId>
	<version>4.2.1</version>
</dependency>
```

В результате код будет выглядеть следующим образом:

```java
// connect to dbus
dbusConn = DBusConnectionBuilder.forAddress(address).withShared(false).build();
// find bluez
ObjectManager adapter = dbusConn.getRemoteObject("org.bluez", "/", ObjectManager.class);
// find service manager from all registered services
DBusPath serviceManagerPath = getServiceManagerPath(adapter);
// find service manager and advertising manager
serviceManager = dbusConn.getRemoteObject("org.bluez", serviceManagerPath.getPath(), GattManager1.class);
advertisingManager = dbusConn.getRemoteObject("org.bluez", serviceManagerPath.getPath(), LEAdvertisingManager1.class);
// create hierarchy of characteristics and services
application = new BleApplication(allServices);
// export them into D-Bus
exportAll(dbusConn, application);
// register application in bluez
serviceManager.RegisterApplication(new DBusPath(application.getObjectPath()), new HashMap<>());
// create advertisement object
advertisement = new BleAdvertisement("/org/bluez/r2cloud/advertisement0", "r2cloud", "peripheral", LORA_SERVICE_UUID);
// and export it to D-Bus
dbusConn.exportObject(advertisement);
// register advertisement in bluez
advertisingManager.RegisterAdvertisement(new DBusPath(advertisement.getObjectPath()), new HashMap<>());
```

## Взаимодействие с r2cloud

Последним шагом будет непосредственно реализация протокола между ESP32 и r2cloud. Я решил сделать один сервис с двумя свойствами:

 * Расписание. При чтении из него возвращаются параметры следующего наблюдения. Запись в это свойство означает полученный пакет. Немного странно, но сильно упрощает код на стороне ESP32.
 * Статус. Служит для получения уровня заряда батареи и bluetooth сигнала.

Эти параметры можно добавить в мониторинг или просто показывать в UI:
 
![](/img/ble-server-java/6.png)
