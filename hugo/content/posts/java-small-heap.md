---
title: "Java и без 16Gb памяти?"
date: 2017-07-16T15:11:18+01:00
draft: false
cover: /img/java-small-heap/0ebcb88f4c7d47cc96e872f9c182638c.jpg
tags:
  - java
  - raspberrypi
  - спутники
  - memory
---
Однажды меня посетила мысль о том, что надо закодить что-нибудь на Java для RaspberryPI. Предыстория того, как я дошёл до жизни такой, сама по себе потянет на отдельный пост. Но вот сочные технические подробности, трудности и счастливый конец ниже под катом.

![](/img/java-small-heap/0ebcb88f4c7d47cc96e872f9c182638c.jpg)

Постановка задачи
------------------

Немного разочаровавшись в движении проекта <a href="https://satnogs.org">satnogs</a>, я решил попробовать сам написать базовую станцию для приёма радио сигналов на <a href="https://www.raspberrypi.org">raspberry pi</a>. Проанализировав текущую функциональность satnogs и сложив с собственным заскорузлым enterprise пониманием того, что такое стабильная платформа, я придумал следующие требования: 

<ul>
	<li>java вместо python. Конечно же.</li>
<li>низкое потребление ресурсов. Embedded же.</li>
<li>переиспользование уже существующих библиотек. Цель проекта не научиться декодировать самому, а максимально интегрировать уже существующие библиотеки</li>
<li>стабильность. Коробочка должна работать сама по себе как можно дольше. В идеале её нужно настроить и забыть.</li>
</ul>

В результате в противоречие вступают только два требования: Java и низкое потребление ресурсов.

В этот момент я почему то вспомнил древний древний слоган "Java - write once, run everywhere" и присказку, что Java может запускаться на кофеварке. С этого момента началось погружение в Java Embedded.

Если вкратце, то в Java существуют две платформы для написания под маленькие устройства: <a href="https://ru.wikipedia.org/wiki/Java_Platform,_Micro_Edition">Java ME</a> и Java Embedded. Первая платформа предназначена для совсем маленьких (кофеварки) устройств, а вторая для тех, что чуть-чуть покрупнее. Я выбрал Java Embedded. 

Сама Java Embedded в Java 8 претерпела изменения. Теперь её можно собрать с различными профайлами: compact1, compact2, compact3. По сути, это depedency management для бедных. Каждый профайл содержит <a href="http://www.oracle.com/technetwork/java/embedded/resources/tech/compact-profiles-overview-2157132.html">какие-то части rt.jar</a>, тем самым уменьшая минимальное потребление памяти JVM при загрузке. На моих как-бы тестах (колонка %RES в выводе команды top), я получил следующее потребление:

<ul>
	<li>compact1 - <b>10mb</b></li>
	<li>compact2 - <b>12mb</b></li>
</ul>

Для начала я выбрал самый хардкорный вариант: compact1. Нo если не получится найти под него библиотеки, то можно попробовать compact2. 

После выбора версии Java нужно выбрать библиотеки. И вот тут дикий-дикий запад. Поскольку в Java мире всё течёт неспеша и с оглядкой на обратную совместимость, то никто из разработчиков библиотек не побежал оптимизировать свой код под новые профайлы. Тем более скоро выходит Java 9, где всё может ещё раз измениться.

Дальше я проанализировал, минимальный набор библиотек для создания не слишком нагруженного web приложения.

<h3>IoC фреймворк</h3>
<ul>
<li><a href="https://github.com/google/dagger">Dagger</a>, <a href="https://github.com/zsoltherpai/feather">Feather</a> - нет @PreDestroy, @PostConstruct и принципиально не планируется. Про graceful shutdown разработчики видимо не слышали. Вручную контролировать последовательность вызова метода start, чтобы при остановке в обратном порядке вызвать stop, совсем не хочется делать. </li>
<li><a href="https://github.com/google/guice">Guice</a> - зависимость на <a href="https://github.com/google/guava">guava</a>, а значит ещё +2mb.</li>
<li><a href="http://picocontainer.com">picocontainer</a> - не compact1</li>
</ul>

<h3>База данных</h3>

Какой же Java проект без базы данных. Но тут есть один подвох: в compact1 нет java.sql api. Поэтому я первым делом посмотрел на базы с native api без jdbc:

<ul>
	<li><a href="http://www.oracle.com/technetwork/database/berkeleydb/overview/index-093405.html">berkleydb</a>. NoSQL, но почему-то зависит от javax.transactional. </li>
</ul>

И с jdbc:

<ul>
	<li> <a href="https://github.com/xerial/sqlite-jdbc">sqlite</a> - библиотека весит 5mb. Видимо содержит все нативные библиотеки для всех платформ.</li>
<li><a href="https://github.com/xerial/sqlite-jdbc">java db</a>. Весит конечно много и разные версии отличаются существенно: 10.8 - 2.5mb, 10.13 - 3.1mb. </li>
</ul>

Есть ещё куча других мелких непонятных embedded баз данных, которые можно было бы попробовать. Но отлавливать их баги под raspberry pi у меня желания нет. 

Зато есть пара других идей:

- А что, если обхитрить JVM: взять compact1 и вручную подложить <a href="https://mvnrepository.com/artifact/org.xerial.thirdparty/jdbc-api/1.4">java.sql api</a>? Ответ: не получится. В Classloader есть вот такой замечательный код:

	```java       
	       if ((name != null) && name.startsWith("java.")) {
	            throw new SecurityException
	                ("Prohibited package name: " +
	                 name.substring(0, name.lastIndexOf('.')));
	        }
	```

	Вообще непонятно почему существует такой maven артефакт, если его даже теоретически нельзя загрузить.
- А может без базы? Для моих целей вполне подходят обычные файлы. Sql join тоже вроде не имеет смысла делать.

В общем отказался совсем от базы. Посмотрим надолго ли.

<h3>Web container</h3>
<ul>
	<li><a href="https://github.com/apache/tomcat">tomcat</a> - Ха-ха-ха</li>
<li><a href="http://www.eclipse.org/jetty/">jetty</a> - не compact1  </li>
<li><a href="https://github.com/NanoHttpd/nanohttpd">nanohttpd</a> - не servlet, нет поддержки сессий. Но видимо такова судьба Embedded разработчика. </li>
</ul>

<h3>SSL temination</h3>
<ul>
	<li>nginx. 3mb master node + 3mb 1 client worker. = 6mb. Вроде неплохо. </li>
</ul>

<h3>Вэб клиент</h3>
<ul>
	<li>angular, reactjs - на ровном месте привносят десяток короткоживущих технологий. </li>
<li>good-o-templates - наш выбор же.</li>
</ul>

<h3>Шаблонизаторы</h3>
<ul>
	<li>JSP - слишком тяжело и нужно много библиотек. Даже не стал копать.</li>
<li>Freemarker - легко, но как оказалось не compact1.</li>
<li>Кто-нибудь слышал про <a href="http://jtwig.org">jtwig</a>? Я тоже нет, но они умееют работать в compact1 и поддерживают базовые фичи. </li>
</ul>

<h3>Логирование</h3>
<ul>
	<li>logback - <a href="https://jira.qos.ch/browse/LOGBACK-1071">только</a> compact3 </li>
<li>log4j - full JRE</li>
<li>java.util.logging? - Хуже уже не будет.</li>
</ul>

<h3>Json</h3>
<ul>
	<li><a href="https://github.com/google/gson">gson</a>. Зависимость на java.sql (!!!)</li>
<li><a href="https://github.com/FasterXML/jackson-databind">jacksonxml</a>. Зависимость на org.w3c.dom.Node</li>
<li>очередной "нагуглил-ночью" код <a href="https://github.com/ralfstx/minimal-json">https://github.com/ralfstx/minimal-json</a>. Посмотрел, вроде там нечему ломаться.</li>
</ul>

После нескольких запусков и сборке всего вместе выплыло несколько косяков, но их можно поправить конфигурацией. Например: 
<a href="https://stackoverflow.com/questions/13825403/java-how-to-get-logger-to-work-in-shutdown-hook">https://stackoverflow.com/questions/13825403/java-how-to-get-logger-to-work-in-shutdown-hook</a>

<h2>Итого</h2>
<ul>
	<li>все библиотеки в сборе + прогретый кэш для шаблонизатора занимают в памяти ~<b>23mb</b></li>
<li>код открыт и доступен: <a href="https://github.com/dernasherbrezon/r2cloud">https://github.com/dernasherbrezon/r2cloud</a> (надеюсь пароли нигде там не закоммитил)</li>
</ul>