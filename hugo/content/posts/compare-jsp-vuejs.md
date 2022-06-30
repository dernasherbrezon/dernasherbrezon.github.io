---
title: "Сравнение JSP и VueJS"
date: 2019-12-15T07:14:18+01:00
draft: false
cover: /img/compare-jsp-vuejs/2.png
emoji: true
tags:
  - jsp
  - java
  - jstl
  - vuejs
  - javascript
  - дизайн
---
Споры о том, насколько SPA лучше или хуже проверенных серверных технологий, не утихают до сих пор. Сторонники SPA (React, Angular, VueJS) в один голос говорят насколько это просто и удобно. Сторонники серверных технологий (PHP, JSP, ASP) ничего не говорят, потому что их мало и они заняты разработкой. Из-за того, что оба подхода достаточно разные, то и сравнивать их очень сложно. Зачастую сравнение сваливается во вкусовщину, так как нет людей, которые бы разрабатывали как с помощью одних, так и с помощью других. И даже если такие уникумы находятся, никто в здравом уме не будет реализовывать сложную функциональность одновременно и на той, и на другой технологии. Кроме меня.

> TL;TR Я смог разработать такой компонент без каких-либо сложностей.

![](/img/compare-jsp-vuejs/2.png)

## Начало

Так получилось, что [r2server](https://r2server.ru) написан с помощью [JSP](https://ru.wikipedia.org/wiki/JavaServer_Pages), а [r2cloud-ui](https://github.com/dernasherbrezon/r2cloud-ui) с помощью [VueJS](https://vuejs.org). И вот мне понадобилось реализовать компонент по отображению [OpenAPI](https://swagger.io/docs/specification/about/) в обоих проектах. В этот момент возникла уникальная ситуация:

 - Нужно реализовать абсолютно одинаковый компонент как в r2cloud-ui, так и в r2server.
 - У него должен быть один и тот же дизайн - [bootstrap4](https://getbootstrap.com). Несмотря на то, что приложения разные, я решил сделать максимально похожий user experience. Это удобно по нескольким причинам: во-первых, достаточно знать один набор компонент, во-вторых, пользователи, вполне очевидно, будут использовать и то, и другое приложение.

## Требования

![](/img/compare-jsp-vuejs/3.png)

Прежде, чем начать сравнивать фреймворки, я хотел бы описать требования:

 - компонент должен быть не зависимым от приложения. Это прежде всего значит, что его можно встраивать не только в моё приложение, но и в любое другое.
 - он должен отображать описание OpenAPI с помощью bootstrap4. Это описание должно быть максимально похожим на стандартный [swagger-ui](https://petstore.swagger.io).
 - (опционально) 80% покрытия тестами.

После того как были определены требования, я без проблем написал необходимый код. Результаты моих ощущений ниже.

## Простота старта

<span style="color: green;">JSP</span> vs <span style="color: red;">VueJS</span>

Для JSP начало работы достаточно простое:

 - создать стандартный maven проект 
 - положить описание в ```/META-INF/tags```
 
Однако, для VueJS старт очень запутанный. Я открыл [официальный гид](https://ru.vuejs.org/v2/cookbook/packaging-sfc-for-npm.html) по созданию компонентов и увидел, что там рекомендуется начать с конфигурации [rollup](https://rollupjs.org/guide/en/). Несмотря на то, что стандартом индустрии является [webpack](https://webpack.js.org), я не нашёл упоминания о нём в документации. rollup действительно позволяет быстро начать разрабатывать компонент, но как только захочется посмотреть промежуточный результат, то тут ожидается облом. rollup просто компилирует файлы в разные форматы и ни о каком dev сервере речи нет.

```json
"scripts": {
  "build": "npm run build:umd & npm run build:es & npm run build:unpkg",
  "build:umd": "rollup --config build/rollup.config.js --format umd --file dist/vue-openapi-bootstrap.umd.js",
  "build:es": "rollup --config build/rollup.config.js --format es --file dist/vue-openapi-bootstrap.esm.js",
  "build:unpkg": "rollup --config build/rollup.config.js --format iife --file dist/vue-openapi-bootstrap.min.js"
}
```

## Простота упаковки

<span style="color: green;">JSP</span> vs <span style="color: green;">VueJS</span>

Тут у обоих фреймворков нет проблем. Для JSP упаковка - это стандартная команда maven:

```
mvn package
```

В VueJS соответственно:

```
npm build
```


## Тестирование

<span style="color: green;">JSP</span> vs <span style="color: red;">VueJS</span>

Опять же, из-за rollup и общей путаницы с технологиями, начать тестировать компонент на VueJS нетривиально. Если честно, я так и не осилил переход на webpack с полноценными тестами и покрытием кода.

В JSP же всё относительно просто: я просто скопировал подход для тестирования тэгов, который [использовал ранее]({{< ref "/jsp-tag-testing" >}}) и сразу получил страницу index.html, которая загружается в браузер простым кликом.

![](/img/compare-jsp-vuejs/1.png)

## Скорость разработки

<span style="color: red;">JSP</span> vs <span style="color: green;">VueJS</span>

Да, инженерная мысль шагнула далеко вперед за последние 20 лет и разрабатывать на VuejS получается значительно быстрее. Например, синтаксис чуть более компактный. Сравните вывод одного и того же блока на VueJS:

```
<p>Available values:
{{ param.schema.items.enum.join(', ') }}
</p>
```

И на JSP:

```
<p>Available values:
<c:forEach items="${curParam.schema.items.getEnum()}" var="curEnum" varStatus="enumStatus"><c:if test="${!enumStatus.first}">, </c:if>${curEnum}</c:forEach>
</p>
```

Ещё одной вещью, значительно ускоряющей разработку (не путать со стабильностью кода!), является отсутствие строгой типизации. Сама по себе доменная модель OpenAPI нетривиальная, поэтому в JSP мне приходилось загружать её из JSON с помощью специальной библиотеки ```swagger-parser-v3```. И даже после того, как я её загрузил, мне приходилось делать различные приседания, чтобы сгруппировать объекты в более удобном виде:

```java
private static Map<String, Operation> getOperationsByType(PathItem item) {
	Map<String, Operation> result = new HashMap<>();
	if (item.getGet() != null) {
		result.put("get", item.getGet());
	}
	...
	return result;
}
```

В javascript же такой проблемы не было, так как json - это JavaScript Object Notation. Что как бы намекает на глубокую поддержку внутри самого языка. Из-за этого загрузка выглядела достаточно просто:

```javascript
openapi = response.data
```

Следующей неудобной штукой при разработке были вспомогательные методы. Например, необходимо было в зависимости от http метода отобразить цвет. В VueJS - это делается с помощью объявления метода прямо в файле:

```javascript
methods: { 
  getColorByMethod (method) {
    ...
  }
}
```

И использование (всё в том же файле):

```html
<span :class="`badge ${getColorByMethod(method)}`">
```

В JSP же пришлось объявлять специальные функциональные методы в ```jsp-openapi.tld```:

```xml
<function>
	<name>getColorByMethod</name>
	<function-class>ru.r2cloud.openapi.OpenAPIHelper</function-class>
	<function-signature>java.lang.String getColorByMethod(ru.r2cloud.openapi.OperationDetails)</function-signature>
</function>
```

Описывать их в java коде:

```java
public class OpenAPIHelper {
	public static String getColorByMethod(OperationDetails method) {
		...
	}
}
```

И использовать внутри JSP:

```html
<span class="badge ${openapiHelper:getColorByMethod(method)}">
```

## Простота переиспользования

<span style="color: green;">JSP</span> vs <span style="color: green;">VueJS</span>

Тут оба фреймворка постарались и сделали вполне неплохое переиспользование своих компонент. Подключить jsp tag в проект можно описав зависимость:

```xml
<dependency>
	<groupId>ru.r2cloud.openapi</groupId>
	<artifactId>jsp-openapi</artifactId>
	<version>1.0</version>
</dependency>
```

И добавив на страницу:

```html
<%@ taglib prefix="openapi" uri="https://github.com/dernasherbrezon/jsp-openapi" %>
<openapi:bootstrap4-openapi openapi="${entity}"/>
```

Во VueJS примерно так же просто:

```json
"dependencies": {
  "vue-openapi-bootstrap": "1.0.1"
}
```

Использование на странице:

```html
<template>
	<vue-openapi-bootstrap :openapi="openapi"/>
</template>

<script>
import vueOpenapiBootstrap from 'vue-openapi-bootstrap/src/vue-openapi-bootstrap'
export default {
  components: {vueOpenapiBootstrap}
}
</script>
```

## Выводы

Несмотря на то, что JSP уже почти 20 лет, разрабатывать переиспользуемые компоненты на нём достаточно просто. Конечно, чувствуется возраст технологии и некоторые вещи можно было бы сделать проще. Тем не менее ужасов, которые рисуют поклонники javascript и SPA, нет. При правильном дизайне и тот, и другой фреймворк предоставляют достаточно мощные инструменты для написания и переиспользования компонентов.