---
title: "Работа с Json в 2019 году"
date: 2019-12-04T22:29:18+01:00
draft: false
images: [/img/json-in-2019/2.png]
tags:
  - java
  - jsp
---

## Введение  

В работе над своей небольшой библиотечкой [jsp-openapi](https://github.com/dernasherbrezon/jsp-openapi) мне понадобилось сериализировать Java объекты в JSON. Я, не долго думая, подключил свою любимую библиотеку gson и пошёл дальше. Проект успешно проходил тест и собирался локально. Следующим моим шагом, как обычно, должна была стать сборка в travis-ci и подключение в sonarcloud.

Но что-то [пошло не так](https://travis-ci.org/dernasherbrezon/jsp-openapi/builds/620333411)...

Вот ключевое место лога:

```
Caused by: java.lang.NoClassDefFoundError: java/sql/Time
	at com.google.gson.Gson.&lt;init&gt;(Gson.java:265)
	at com.google.gson.GsonBuilder.create(GsonBuilder.java:597)
```

Оказывается, gson [зависит от пакета java.sql](https://github.com/google/gson/blob/22877d67ba44299e8d77eb841ab20c2087d46752/gson/src/main/java/module-info.java). При сборке jdk9+, библиотека должна создавать файл module-info.java, в котором необходимо описывать эту зависимость. 

В принципе, это не страшно. Я даже уже начал идти этим путем: создал module-info.java, начал разбираться как собирать проект на openjdk11 и oraclejdk8. Но тут меня осенило. Я же разрабатываю библиотеку тэгов. Для JSP. В 2019 году. Какая вообще Java 11? В лучшем случае её будут использовать в Java 8. И ещё. Библиотека рендеринга html ну совсем не может зависеть от java.sql. Тем более, что я нигде не использую эту зависимость. 

Немного взгрустнув, я вздохнул и пошёл сложной дорогой: выбор другой JSON библиотеки.

## Выбор альтернатив

Самое быстрое гугление выдает 3 альтернативы:

- Reference implementation [json-java](https://github.com/stleary/JSON-java).
- [Jackson](https://github.com/FasterXML/jackson)
- [json-p](https://javaee.github.io/jsonp/)

Но прежде, чем выбирать какую-то одну, необходимо определиться с требованиями:

- минимальное количество зависимостей, но без фанатизма. Код всё равно будет выполняться на сервере
- возможность сериализировать POJO.
- возможность отбрасывать null поля. Из-за того, что я не контролирую ```io.swagger.v3.oas.models.OpenAPI```, то я не могу вставить в него аннотации и прочие служебные конструкции. Сериализация null полей должна быть сконфигурирована извне
- возможность pretty print. Получившийся json будет рендериться с помощью тэгов &lt;pre&gt;, поэтому он должен выглядеть хорошо

### json-java

Достаточно простой проект, мало кода, а значит быстро и ничего лишнего. Однако, сериализацию объектов через reflection не поддерживает и её придётся писать самому каждый раз. Не подходит.

### Jackson

Нет, Вы только посмотрите на их readme. Если, с помощью Jackson нельзя собрать космический корабль, то я буду крайне удивлён.

![](/img/json-in-2019/1.png)

После 15 минут вдумчивого анализа оказалось, что для минимальной работы требуется 3 библиотеки:

- jackson-core
- jackson-annotations
- jackson-databind

Скрипя сердцем, отложил, как формально подходящую под требования.

### jsonp

Чтобы начать работать с этой библиотекой, нужно добавить следующие зависимости:

```xml
<dependency>
    <groupId>javax.json</groupId>
    <artifactId>javax.json-api</artifactId>
    <version>1.1</version>
</dependency>

<dependency>
    <groupId>org.glassfish</groupId>
    <artifactId>javax.json</artifactId>
    <version>1.1</version>
</dependency>
```

Ох, только не glassfish. Почему выбор библиотеки может зависить от личных предпочтений? Тем не менее, прочитав случайную [статью](https://blog.overops.com/the-ultimate-json-library-json-simple-vs-gson-vs-jackson-vs-json/) о сравнении сферических коней, решил не брать jsonp по более объективным причинам: низкая производительность.

## Вывод

Jackson, конечно, уступает в удобстве работы gson. Но за неимением лучшего пришлось выбрать его:

```java
JsonFactory jsonFactory = new JsonFactory();
jsonFactory.configure(JsonGenerator.Feature.AUTO_CLOSE_TARGET, false);
ObjectMapper mapper = new ObjectMapper(jsonFactory);
mapper.enable(SerializationFeature.INDENT_OUTPUT);
mapper.setSerializationInclusion(Include.NON_NULL);
mapper.writeValue(w, value.getProperties());
```

На этом я не остановился и [выразил свою позицию](https://github.com/google/gson/issues/1629) разработчикам gson. Шансы, что эту задачу реализуют, крайне малы, так как это значит отказываться от обратной совместимости с предыдущими версиями. И на такое разработчики вряд ли пойдут.