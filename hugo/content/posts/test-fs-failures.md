---
title: "Тестирование ошибок файловой системы"
date: 2019-04-20T21:50:18+01:00
draft: false
tags:
  - java
  - тестирование
---
Большинство статей в моём блоге посвящены интересным вещам, с которыми я периодически сталкиваюсь. Эта статья не исключение. В одном из моих проектов - [r2cloud](http://github.com/dernasherbrezon/r2cloud) я столкнулся с одной интересной ошибкой.

Вот, что мне удалось восстановить глядя на логи и исходный код:

 1. Диск полностью заполнился
 2. В какой-то момент времени обновилась конфигурация. Например, обновилось текущее значение [PPM](https://davidnelson.me/?p=371)
 3. При попытке записать в файл, происходит ошибка IOException "no disk space"
 4. Файл пользовательских настроек полностью портится. В зависимости от того, сколько диска было свободно, он становится либо частично записанным, либо пустым. 

Эта ошибка достаточно критичная. Дело в том, что с появлением большого количества спутников, диск будет периодически заполнятся. То есть, "no disk space" будет достаточно часто возникать. При этом пользовательские настройки не должны пропадать! Даже если диск полностью заполнен, приложение должно работать и отправлять в [r2server](https://r2server.com) данные.

Исправить эту ошибку достаточно просто, однако, возникает немаловажный вопрос: а как вообще тестировать отказ файловой системы? И "no disk space" в частности?

## Теория

До JDK7 необходимо было бы создавать ещё один слой абстракции над файловой системой и делать его mock во время тестирования. В JDK7 появился специальный слой, абстрагирующий файловую систему: ```java.nio.file.FileSystem```. Изначально [r2cloud](http://github.com/dernasherbrezon/r2cloud) был написан на основе старого ```java.io.File```, поэтому его необходимо переписать на новый API:

![](api.png)

## MockFileSystem

Во время тестирования FileSystem необходимо заменить на MockFileSystem, которая генерирует IOException по заранее сконфигурированному сценарию. К сожалению, я не нашёл такую файловую систему, поэтому написал свою [mockfs](http://github.com/dernasherbrezon/mockfs).

Она позволяет проксировать запросы к файловой системе по-умолчанию и генерировать IOException при доступе к определённым файлам. 

Тест при этом выглядит следующим образом.

Инициалиация. Чтобы MockFileSystem использовалась, необходимо её передавать компонентам извне.

```java
	@Before
	public void start() throws Exception {
		fs = new MockFileSystem(FileSystems.getDefault());
		config = new TestConfiguration(tempFolder, fs);
	}
``` 

Сам тест при этом выглядит следующим образом:

```java
	@Test
	public void testCorruptedAfterFailedWrite() throws Exception {
		String lat = "53.40";
		config.setProperty("locaiton.lat", lat);
		config.update();

		fs.mock(config.getTempDirectoryPath(), new FailingByteChannelCallback(3));
		Path userParentPath = fs.getPath(TestConfiguration.getUserSettingsLocation(tempFolder)).getParent();
		fs.mock(userParentPath, new FailingByteChannelCallback(3));

		String newLat = "23.40";
		config.setProperty("locaiton.lat", newLat);
		try {
			config.update();
			fail("config should not be updated");
		} catch (Exception e) {
			// expected
		}
		
		fs.removeMock(config.getTempDirectoryPath());
		fs.removeMock(userParentPath);

		config = new TestConfiguration(tempFolder, fs);
		assertEquals(lat, config.getProperty("locaiton.lat"));
	}
```

 * В самом начале происходит запись в файл.
 * Потом идёт установка поведения файловой системы. В данной случае MockFileSystem будет выбрасывать IOException после записи 3 байт.
 * Очистка mock объектов.
 * Загрузка данных из файла и проверка того, что предыдущее значение успешно было загружено.
 
После того, как тест был написан, исправление ошибки достаточно простое: 

 * делать запись во временный файл 
 * атомарно перезаписывать временный файл в результирующий
 