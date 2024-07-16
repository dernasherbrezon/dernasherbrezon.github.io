---
title: "Distributing Java application"
date: 2015-08-18T13:55:18+01:00
draft: false
tags:
  - java
  - ubuntu
  - deb
  - admin
  - s3
  - maven
---
![](img/75bbd9f6074d4cb8a46ad705051aa8e0.png)

Surprisingly, but a fact - distributing Java applications in the 21st century is still a huge hassle. Developers still come up with methods like rsync/copy-paste/wget to install Java applications on servers. And only monstrous enterprise production-ready platforms sometimes allow a bit more - rolling back the application to a previous version. In this article, I would like to talk about an accessible and straightforward way of organizing distribution.

## deb и apt

In the world, there are many truly gigantic repositories of applications and tools for their distribution. The largest, by perception, are AppStore, Google Play, Debian/Ubuntu repositories, and CentOS/Fedora YUM repositories. For example, in the Ubuntu repositories for version 15.04, there are about 90,000 applications (excluding various versions). Why not use a time-tested system for distributing Java applications? Especially considering that:

- [Most](http://w3techs.com/technologies/details/os-linux/all/all) servers already use Debian/Ubuntu.
- It's a time-tested tool: the first release was [16 years](https://en.wikipedia.org/wiki/Advanced_Packaging_Tool) ago
- Native support in the operating system.

To begin with, let's talk a bit about the application distribution system in Debian/Ubuntu. It consists of two main parts:

- deb packages
- apt (Advanced Package Tool) tools

## deb пакеты

deb is a binary distribution of an application. It consists of three main parts:

- metadata. Manufacturer, version, dependencies on other packages (very similar to Maven), description, etc.
- the application itself. .tar.gz archive
- (optional) scripts that will be executed during installation

The structure of the .tar.gz archive can be completely custom. However, for your application to resemble all other applications on the system, it must follow the Debian/Ubuntu directory structure:

- /etc - configs
- /etc/init.d/ - daemon startup scripts
- /usr/bin - executable files
- /usr/lib - libraries
- /var/log - logs

Depending on your application, the directories may differ slightly, but the overall structure should be pretty clear.

Another important feature of deb packages is the ability to run scripts during installation. These scripts are also stored in the deb package and have standard naming. Each script can be executed in a specific installation phase. The installation of a package is divided into several phases:

- preinst
- inst
- postinst
- prerm
- rm
- postrm

There are many different intermediate phases and different combinations of installation states. We are not very interested in them, but for those who want to understand, you can read the [official documentation](https://www.debian.org/doc/debian-policy/ch-maintainerscripts.html). Typically, these scripts configure log rotation and archiving, set initial configuration values (e.g., root password for MySQL). If you have a final business application, it's better to use a proper automation tool like [Ansible](http://www.ansible.com/home), [Chief](https://www.chef.io/chef/), [Puppet](https://puppetlabs.com).

## apt

apt is a set of tools for working with deb packages. It allows you to:

- configure repositories and work with them: add, remove, change, update the index
- manage packages: install, remove, update, search

In a simplified form, an apt repository is an HTTP server that distributes deb packages. It has an index (file) that is available at the standard path, and binaries.

## Bringing It All Together

Once clear what deb and apt are and how to use them, let's try to do something:

- create a deb package in the package phase
- publish the resulting package in the deploy phase

To archive we can choose one of the existing plugins.

## [jdeb](https://github.com/tcurdt/jdeb)

The scheme of its work is [quite simple](https://github.com/tcurdt/jdeb/blob/master/src/examples/maven/pom.xml):

- list the files and directories that will go into the resulting .tar.gz archive
- specify permissions

More detailed documentation on the capabilities of the plugin can be found on the official [page](https://github.com/tcurdt/jdeb/blob/master/docs/maven.md).

## [apt-maven-plugin](https://github.com/dernasherbrezon/apt-maven-plugin)

It works with the repository specified in distributionManagement as an apt repository, not a Maven repository. Although there is nothing stopping them from being used simultaneously under one URL. Their layouts are compatible with each other.

The example configuration looks like this:

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

And the distributionManagement section (nothing [unusual](https://maven.apache.org/plugins/maven-deploy-plugin/usage.html)):

```xml
<distributionManagement>
	<repository>
		<id>maven-release-repo</id>
		<url>http://example.com/maven</url>
	</repository>
</distributionManagement>
```

After the deploy phase is executed, http://example.com/maven will become both a Maven and an apt repository. And you can confidently write:

```bash
sudo add-apt-repository "deb http://example.com/maven strepo main"
sudo apt-get update
sudo apt-get install <artifactId>
```

## And a pinch of Enterprise

The mantra of every Java enterprise developer sounds like this:

- security
- stability
- high availability production ready platform

All of this is perfectly solved by creating an apt repository from the most popular hosting for developers: [s3](https://aws.amazon.com/s3/). Together with CloudFront, it guarantees [99.9%](https://aws.amazon.com/s3/sla/) reliability and geographical [distribution](https://www.google.com/maps/d/viewer?mid=zq41xmfbtRfA.kUKJZcl-4O7k&hl=en).

This is also quite simple to do. You need to connect the plugin for working with S3:

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

Change the URL in the distributionManagement section to the bucket's name:

```xml
<distributionManagement>
	<repository>
		<id>maven-release-repo</id>
		<url>s3://example.bucket</url>
	</repository>
</distributionManagement>
```

And configure access to your bucket:

```xml
<servers>
	<server>  
		<id>maven-release-repo</id>  
		<username>apikey</username>  
		<password>apisecret</password>  
	</server>
</servers>
```

On the end servers to access such a repository, there is a special plugin: [apt-transport-s3](https://launchpad.net/~leonard-ehrenfried/+archive/ubuntu/apt-transport-s3). Unfortunately, it is not yet in the official repositories, so you need to manually add one of the repositories where it is contained:

```bash
sudo add-apt-repository ppa:leonard-ehrenfried/apt-transport-s3
sudo apt-get install apt-transport-s3
```

After that, you can point to S3 repository:

```bash
sudo add-apt-repository "deb s3://apikey:apisecret@s3.amazonaws.com/example.bucket strepo main"
```

## Conclusion

After all the manipulations, installing the application is as simple as:

- mvn clean deploy

On any Debian/Ubuntu server anywhere in the world:

- apt-get update
- apt-get install artifactId