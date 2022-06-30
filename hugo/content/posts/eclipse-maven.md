---
title: "Интеграция Eclipse и Maven"
date: 2009-01-10T13:14:18+01:00
draft: false
tags:
  - java
  - maven
  - eclipse
---
Maven в Eclipse - это очень удобно.

Однако при всех достоинствах каждого есть некоторые неудобства интеграции. Например, следующий вариант:
Есть проект. В нём есть основные исходные коды и для тестов. Соответственно они находятся в разных папках. Есть два builder'а. Стандартный JDT и Maven Builder. Я не сильно вдавался в детали их работы, но в первом приближении они компилируют. JDT'шный стандартно в output folder для Eclipse'a, а maven'овский я так понимаю выполняет target compile и помещает скомпилированные классы в target/classes & target/test-classes (по дефолту).

Вот тут то и возникает проблема. Вернее маленькое неудобство. Хочется выполнять тесты с помощью JUnit'a встроенного в Eclipse. Потому что удобно. Однако он как то странно интегрирован с maven'ом и похоже видит только классы скомпилированные JDT. Поэтому если нажать Run -> JUnit Test то можно увидеть сообщение: NoClassDefFoundError: /my/test/Class

Решение проблемы два:

  1. Выполнять компиляцию тестов с помощью maven'а, а затем выполнять запуск junit тестов. Но это же слишком неудобно? Каждый раз при изменении класса запускать компиляцию maven'ом, поэтому есть ещё один путь.
  2. Написать нехитрые настройки.
  
У каждого maven-проекта есть родительским pom. Поэтому в родительском pom'е нужно:
  
```xml
<build>  
    <outputdirectory>${output.dir}</outputdirectory>  
    <testoutputdirectory>${testoutput.dir}</testoutputdirectory>  
    ...  
</build>  
  
<properties>  
    <output.dir>${basedir}/target/classes</output.dir>  
    <testoutput.dir>${basedir}/target/test-classes</testoutput.dir>  
</properties>  
   
<profiles>  
    <profile>  
        <id>eclipse-folders</id>  
        <properties>  
            <output.dir>${basedir}/target/eclipse</output.dir>  
            <testoutput.dir>${basedir}/target/eclipse</testoutput.dir>  
        </properties>  
    </profile>  
</profiles>
```

В настройках проекта:

  * Maven -> Active Maven Profiles написать "eclipse-folders"
  * Java build Path -> Default Output Folder написать "target/eclipse" и в настройках папок ресурсов (типа "/src/test/resources") удалить Excluded чтобы ресурсы подцеплялись при запуске тестов (например log4j.properties)
  
Я ещё отключил Maven Builder. Но думаю это необязательно.