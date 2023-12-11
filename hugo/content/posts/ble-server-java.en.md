---
title: "BLE server using Java"
date: 2023-01-17T08:22:17+01:00
draft: false
tags:
  - java
  - bluetooth
  - r2cloud
---
In one of my [previous posts]({{< ref "/lora-deep-sleep" >}}), I began optimizing the power consumption of ESP32 and LoRa. The idea was to put the microcontroller to sleep and wake it up only when data received. But how to know when to wake up? It all depends on the specific application. If you need to transmit data at regular intervals, you can hardcode it in the firmware. But what if data needs to be received at unpredictable intervals? In my project [r2cloud](https://github.com/dernasherbrezon/r2cloud), that's precisely the case.

## Workflow

r2cloud creates a schedule for satellite passes based on various parameters. As soon as a satellite is in the field of view, data reception begins. Once the satellite goes below the horizon, the signal is processed and sent to the server.

ESP32 needs to receive the start time of the next observation from the server and then go to sleep. Upon waking up, it needs to fetch the parameters again and start receiving the signal. The workflow can be described with a sequence diagram:

{{< svg "/img/ble-server-java/2.svg" >}}

In this diagram, communication between ESP32 and r2cloud is minimized to save energy. Additionally, the microcontroller acts as an active component that initiates all interactions, solving the problem of polling data, timeouts, and more.

Now, the next step is to determine how ESP32 should receive data from the server. There are several options:

 * Wired connection through a serial interface. However, this defeats the purpose of deep sleep and energy savings, as a wired connection can also provide power.
 * LoRa. This seems enticing. ESP32 receives data from the satellite and retransmits it. A [LoRa module on RaspberryPI]({{< ref "/lora-raspberrypi" >}}) receives the data and sends it to r2cloud. But this requires purchasing a separate LoRa module, soldering, and configuration, making the system more complex.
 * Bluetooth. Available on both ESP32 and RaspberryPI.
 * Wi-Fi. To send a small message, one needs to connect to an access point, encrypt the data, and send it. Not only does this consume a lot of energy, but it also requires a separate access point.
 
I decided to explore Bluetooth and see what can be achieved.

## BLE

BLE (Bluetooth Low Energy) is a wireless technology with low power consumption. Its main idea is that two devices do not have to keep the connection constantly active, thereby saving energy. Instead, there are special "profiles" - GAP and GATT, which provide a software model for sending short messages between two devices. From a programmer's perspective, it looks as if the two devices are connected and active.

Every device that wants to provide access to its capabilities via BLE must create a tree-like structure of properties, methods, and services in memory. This structure is defined in the GATT (Generic Attribute Profile) specification.

{{< svg "/img/ble-server-java/3.svg" >}}

As an example, I connected to my watch using the program [nRF Connect](https://www.nordicsemi.com/Products/Development-tools/nrf-connect-for-desktop):

![](/img/ble-server-java/1.png)

On the right, you can see part of the public information that the device publishes:

 * Service "Device information"
   * Characteristic "Model Number String"
   * Characteristic "Manufacturer Name String"

I need to create very similar structure on RaspberryPI and expose it for ESP32. However here come some difficulties due to different operating systems and APIs.

## Bluez

To work with Bluetooth in Linux, a complete stack called [bluez](https://github.com/bluez/bluez) is used. In this context, the stack implies a set of drivers for Linux and implementations of various Bluetooth profiles that can operate at different levels of the OSI model. This also includes various programs for managing Bluetooth, such as hcitool or gatttool.

In my case, the most interesting bluez profiles are GAP and GATT. The first is a lightweight device discovery protocol, and the second is a way to organize objects and fields in a tree.

bluez allows you to control the device using D-Bus interfaces and objects.

## D-Bus

D-Bus is a system for interprocess communication in Linux. It serves as a kind of central bus through which applications can send signals, invoke methods, and retrieve properties from one another.

![](/img/ble-server-java/4.png)

bluez creates a tree of objects and properties in D-Bus for each connected device. By working with these objects, you can receive or send data to the devices. It's a bit intricate, but this approach allows you to connect several different Bluetooth devices to one physical Bluetooth chip and work with each of them independently.

In the screenshot above, you can see that bluez created a D-Bus object ```org.bluez.Device1``` for the connected device ```78:DD:08:A3:A7:52```. This device provides access to several services and their properties:

 * service0001
   * characteristic0006
 * service0010
   * characteristic0012
 * service0100
 * service0200
   * characteristic0204
   * characteristic0212
 * service0680
 
In this example, the remote device provides access to its services. But what if you need to do the opposite: expose access to RaspberryPI? For this, you need to write an application that registers the necessary services in bluez.

## GATT Server

In general, the scheme looks like this:

{{< svg "/img/ble-server-java/5.svg" >}}

The application must create a structure of services and their properties in D-Bus:

 * Services must implement the interface ```org.bluez.GattService1```
 * Properties must implement the interface ```org.bluez.GattCharacteristic1```
 
Despite the fact that the interface names look very similar to regular Java objects, they have nothing in common with Java. They are simply strings from the bluez specification.

Once the objects are created, you need to find the Service Manager object in D-Bus and register the application with it. The Service Manager is a D-Bus object that implements the interface ```org.bluez.GattManager1```.

Next, somehow inform all devices in the vicinity about the services supported by RaspberryPI. To do this:

 * Create a D-Bus object of type ```org.bluez.LEAdvertisement1```, which includes a list of services available to external devices
 * Register this object in the Advertising Manager
 
## Integration with Java

So, the task boils down to connecting to D-Bus and registering the necessary services. By default, you can only connect to D-Bus through [unix domain socket (UDS)](https://en.wikipedia.org/wiki/Unix_domain_socket): ```/var/run/dbus/system_bus_socket```. In Java, UDS support appeared only in version 16. Working with them is very similar to regular sockets:

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

But better use existing library like [hypfvieh](https://github.com/hypfvieh). It will provide a nice dbus abstraction and expose all required APIs:

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

The final code might look like this:

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

## Integration with r2cloud

The final step will be the direct implementation of the protocol between ESP32 and r2cloud. I decided to create one service with two properties:

 * Schedule. When read, it returns the parameters of the next observation. Writing to this property signifies the receipt of a packet. It might seem a bit strange, but it greatly simplifies the code on the ESP32 side.
 * Status. Used to obtain the battery level and Bluetooth signal strength.

These parameters can be added to monitoring or simply displayed in the UI:
 
![](/img/ble-server-java/6.png)
