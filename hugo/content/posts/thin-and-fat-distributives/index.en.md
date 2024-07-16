---
title: "Fat and thin distributions"
date: 2020-08-26T22:31:18+01:00
draft: false
tags:
  - java
  - maven
  - admin
---
This week, I finally migrated all my projects to Ubuntu 18.04 and thin .deb distributions. I started this project at the beginning of the year and completed it only now, almost 8 months later. The migration itself deserves a separate article with complaints and rhetorical questions. Here, I want to briefly describe the confrontation between thin and fat distributions, share my perspective on this story, and provide some analysis. Let's dive in!

## Distributions

Almost immediately after writing the first version of any program, the question arises of how to distribute it. In 2020, there are several fairly standard ways:

 * Docker image. The program is compiled, and all dependent libraries are placed in the [storage layer](https://docs.docker.com/storage/storagedriver/)
 * Zip file. All necessary files are simply placed in an archive.
 * Debian package. I wrote a bit about how to build it in [one of my articles]({{< ref "/java-dist" >}})

While Docker images are straightforward, deciding what to include in a zip file or Debian package is not always obvious. There are two diametrically opposed strategies.

## Fat Distributions

The idea is quite simple: let's put all the necessary files and dependent libraries needed for the application to run into the archive. The advantages of this approach include:

 * Almost no dependency on the external environment. It doesn't matter what libraries are already installed in the operating system; the application will bring its own libraries with the required versions.
 * No dependency on other applications. This follows from the fact that all dependencies are inside the fat distribution.
 * Simplicity. Just download one distribution and run it with ```java -jar fatApp.jar```.
 
The disadvantages include:

 * The distribution is very heavy. Because all dependencies are included, the distribution size significantly increases. This affects installation speed (you need to download the distribution from the apt repository or artifactory) and build speed, as well as repository upload speed.
 * As a result, the binary repository size increases significantly. You need to plan a strategy for cleaning up old versions. For example, Docker recently faced the problem of a bloated Docker Hub repository and [decided to delete unused Docker images](https://www.docker.com/pricing/retentionfaq). Deleting old and unused dependencies is a complex and non-trivial task.
 
A prominent supporter of fat distributions is the [spring boot](https://docs.spring.io/spring-boot/docs/2.1.5.RELEASE/reference/html/build-tool-plugins-maven-plugin.html) project. During the  ```package``` phase, they build a fat distribution that can be run with a single command:

```
$ mvn package
$ java -jar target/mymodule-0.0.1-SNAPSHOT.jar
```

## Thin Distributions

Thin distributions are intended to address the issues of fat distributions, but they have their own downsides:

 * Relative complexity. There is no consensus on how to correctly build a slim distribution and deploy it for execution
 * Dependency on other applications. In a classic thin distribution, dependencies are installed in the operating system. But what if one application needs one version of a library, and another application needs a different version? Developers of Linux-like operating systems try to find the least common denominator for thousands of applications and libraries. This is a complex and labor-intensive procedure.
 
The advantages are straightforward:

 * Applications are very lightweight. They can be deployed quickly, and often there is no need to worry about the size of the binary repository.
 * Dependencies are reused between applications. While not very relevant for the Java world, it is in demand for the C/C++ world. The idea is that a library is loaded into memory only once and then used by different applications. This reduces memory consumption and application load time.
 
As I mentioned before, strong advocates of thin distributions are operating systems. Despite the fact that the Ubuntu team decided to create fat distributions (snap packages), the community greeted this idea very coolly and with a dose of skepticism.

## Thin Distributions for Java

In all my projects, I gradually moved away from fat distributions and switched to slim ones. This was important for me for several reasons:

 * Large binary repositories are expensive to maintain. For hobby projects that don't generate income, paying for gigabytes of distributions is costly.
 * Build and repository upload speed. I often work on trains, planes, hotels, where connection speed is limited. Downloading 100 MB of fat distributions can take hours. Meanwhile, downloading ~200 KB takes seconds. It is very convenient and increases productivity.
 
Since there is no consensus on how to create slim distributions, I decided to create my own. To do this, I wrote a small Maven plugin - [deps-maven-plugin](https://github.com/dernasherbrezon/deps-maven-plugin). During the build, it creates three files:

 * repositories.txt - a list of all Maven repositories available in the project.
 * dependencies.txt - a list of all project dependencies.
 * script.sh - a fixed script inside the plugin.

```xml
<plugin>
	<groupId>com.aerse.maven</groupId>
	<artifactId>deps-maven-plugin</artifactId>
	<configuration>
		<repositories>${project.build.directory}/deps/repositories.txt</repositories>
		<dependencies>${project.build.directory}/deps/dependencies.txt</dependencies>
		<script>${project.build.directory}/deps/script.sh</script>
		<excludes>
			<exclude>com.example:*:*<exclude>
		</excludes>
	</configuration>
</plugin>
```

The idea is quite simple: after unpacking the thin distribution, you need to call script.sh and pass it the two generated files. It will download them and place them in the specified folder. This will be the folder with all the dependencies.

Keep in mind that all dependencies must be available in public Maven repositories. If not, you can exclude them in the ```excludes``` section and place them inside the thin artifact.

But what if the artifact changes its version or is removed from the list of dependencies? It's simple: script.sh builds the intersection of dependencies needed in the folder and those already present there. If dependencies have already been downloaded, they will not be downloaded again. If dependencies are no longer used (present in the folder but absent in dependencies.txt), they are deleted from the folder.

After the script finishes, you can run the application. For example, here are the paths for r2cloud:

```
java -cp /home/pi/r2cloud/lib/*:/usr/share/java/r2cloud/* ru.r2cloud.R2Cloud
```

The ```/home/pi/r2cloud/lib/``` folder contains the application itself, while the  ```/usr/share/java/r2cloud/``` folder contains all the application's dependencies.

## Results

In addition to the obvious advantages of thin distributions, there are some less obvious ones. For example, they significantly save traffic when updating r2cloud via a 3G modem. Also, over time, I accumulated about 564.11 MB of r2cloud distributions. This is [about 600](https://travis-ci.org/github/dernasherbrezon/r2cloud) builds!