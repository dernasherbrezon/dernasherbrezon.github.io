---
title: "Восстановление jpeg файлов"
date: 2020-12-16T14:40:18+01:00
draft: false
tags:
  - java
  - jpeg
  - спутники
---

[1kuns-pf](https://db.satnogs.org/satellite/43466) уже давно сгорел в плотных слоях атмосферы, но он оставил яркий след в базе данных Satnogs. Это самый наблюдаемый спутник на текущий момент. За два года своей работы сообщество приняло около 6 миллионов сообщений. 

![](img/1.png)

Я решил посмотреть, что же это за данные и как то нормализировать их. Так как спутник сгорел, то в результате должен получиться законченный датасет, удобный для анализа.

У меня [есть описание формата](https://github.com/dernasherbrezon/jradio/blob/master/src/main/java/ru/r2cloud/jradio/kunspf/KunsPfBeacon.java) трёх типов данных:

 * полная телеметрия (Whole Orbit Data)
 * текущая телеметрия
 * изображения

С первыми двумя всё достаточно просто: нужно сделать дедупликацию данных, распарсить, удалить явно неправильные данные. А вот с изображениями всё гораздо интереснее.

## Формат пакета

Формат пакета, содержащего картинку, очень минималистичный.

{{< svg "img/5.svg" >}}

У него есть только порядковый номер кусочка данных и, собственно, данные. Этого явно недостаточно, чтобы однозначно собирать полноценные изображения из кусочков. Но, чтобы жизнь мёдом не казалась, есть ещё несколько особенностей:

1. спутник может передавать изображения в двух разрешениях: 160х120 и 640х480. Это значит, что общее количество кусочков данных может быть разным. В теории, я бы мог восстановить хотя бы одно изображение и посчитать из скольких кусочков оно состоит. Но это не сработает в 100% случаях, так как:
2. изображение задекодировано в формате jpeg. А это значит, что размер полностью тёмного изображения будет меньше, чем изображение с какой-то информацией. А значит и количество кусочков будет меньше.
3. jpeg файлы передаются простыми фрагментами. Нет ничего похожего на [SSDV]({{< ref "decoding-jy1sat">}}). Если не удалось принять кусочек в середине jpeg файла, то всё изображение после этого кусочка будет потеряно.
4. некоторые изображения передаются друг за другом раз в минуту. В совокупности с 1 пунктом это даёт очень сильные ошибки при склеивании фрагментов. Об этом чуть ниже.

В принципе, пункты с первого по третий достаточно просто обойти. Можно посмотреть на данные и эмпирически выявить максимальное количество кусочков для маленьких изображений. Допустим, это 15. Тогда всё, что больше - это кусочки большого изображения. Правда, это не даёт 100% гарантии. Например, можно получить только первые 15 кусочков большого изображения и результат получится неправильным.

Гораздо сложнее с пунктом 4. Чтобы его осознать, нужно понять как хранятся данные в базе и как они туда попадают.

{{< svg "img/6.svg" >}}

За одним спутником может наблюдать несколько станций. Все они могут принять как одинаковые фрагменты, так и разные. После того как фрагмент принят станция добавляет к него время и отправляет на сервер. Это, в свою очередь, создаёт дополнительные сложности:

1. Нельзя полагаться на время получения фрагмента. Часы всех станций не синхронизированы. Скорость декодирования сигнала тоже. Время на отправку фрагментов по сети на сервер, тоже разное. Всё это приводит к тому, что кусочки оказываются перемешаны
2. Кусочки последующего изображения могут быть перемешаны с кусочками предыдущего. А так как нет сквозной нумерации пакетов, то нельзя однозначно сказать к какому изображению относится порядковый номер к текущему или уже следующему.

Из всего этого ясно одно - гарантированно восстановить изображения не получится. А насколько хорошо получится? Я задался целью написать такой алгоритм, который бы позволил восстановить максимальное количество изображений. 

## Заголовок файла

Самой первой идеей, которая пришла мне в голову, было восстановление повреждённого заголовка jpeg файла. Если заголовок всех jpeg файлов будет одинаковый, то я могу его захардкодить и подставлять во все файлы. Для этого нужно найти сколько фрагментов занимать заголовок. Я взял полностью восстановленное изображение и просто посчитал. Получилось 4.5 фрагмента: индексы 0, 1, 2, 3 и половинка 4-го.

Я написал достаточно простой Java код, чтобы проверить теорию:

```java
Map<Integer, byte[]> dataByChunkId = new HashMap<>();
for (KunsPfBeacon beacon : data) {
	int chunkId = beacon.getImageChunk().getImageBlock();
	if (chunkId > 3) {
		continue;
	}
	byte[] chunkData = beacon.getImageChunk().getImageChunk();
	byte[] previous = dataByChunkId.get(chunkId);
	if (previous == null) {
		dataByChunkId.put(chunkId, chunkData);
	} else {
		if (!Arrays.equals(previous, chunkData)) {
			System.err.println("non equal!");
			break;
		}
	}
}
```

И оказалось, что мои выводы неверные! Где-то в мае 2020 спутник попытался передать картинку в разрешении 1600x1200 и с другими таблицами Хаффмана. К сожалению, это был единственный случай передачи такой большой картинки, да и сама она содержала только первые 14 кусочков. В итоге я решил её отбросить и сделать фиксированный jpeg заголовок. 

Осталось разобраться, что делать с кусочком номер 4. Он наполовину состоит из заголовка jpeg и наполовину из данных. Если этого кусочка нет, то можно восстановить хоть что-то, правда, результат будет выглядеть достаточно странновато:

![](img/2.jpg)

С этим ничего не поделаешь. Если данных нет, то их нет.

## Алгоритм сортировки

Вот тут кроется самый сок. Дело в том, что при правильной сортировке кусочков изображения, можно получить больше правильных результатов.

Для начала я попробовал тривиальный алгоритм:

 * сортировать по времени
 * если следующий кусочек имеет индекс меньше, чем предыдущий, то он принадлежит уже следующему изображению
 * взять текущий список кусочков и составить из них изображение

![](img/3.jpg)

Получилось достаточно неплохо, но когда передаются последовательно несколько изображений, то оба могут получиться "битыми". Я попробовал ограничить время получения одного изображения десятью минутами, восемью и пятью. Результат получился хорошим при десяти минутах.

![](img/4.jpg)

Тем не менее, если кусочки сильно перемешаны, то результат по-прежнему так себе. 

Следующей по списку идёт более фундаментальная идея. Декодировать jpeg. Сейчас я просто формирую массив байтов и говорю java, что в нём находится jpeg файл. Массив байтов парсится и получается то, что получается. Даже если изображение частично повреждено, то нативный libjpeg, который используется в java, спокойно это обработает и попробует выдать хоть что-то. Но если написать свой собственный декодер, то можно будет сделать вот такой алгоритм:

 * сортировать по времени
 * просмотреть вперёд на 10 минут и найти кусочек с индексом 4 (0,1,2,3 - фиксированные. их можно игнорировать)
 * добавить его к текущим
 * попробовать декодировать
 * если DC коэффициент не найден или AC коэффициент не найден, то скорей всего кусочек от другого изображения. Искать дальше 
 * если найден, то начать искать кусочек с индексом 5. И так далее
 
Этот алгоритм гораздо серьёзнее, но для него придётся расчехлить знания по структуре jpeg файлов. Хорошо, что я [сделал для себя заметку о кодировании jpeg файлов]({{< ref "/jpeg-encoding" >}}).

_Спустя какое-то время_

Ничего не получилось. Я реализовал [специальный jpeg декодер](https://github.com/dernasherbrezon/jradio/blob/master/src/test/java/ru/r2cloud/jradio/jpeg/validator/JpegValidator.java), который проверяет входящие кусочки изображений. И даже [написал тест](https://github.com/dernasherbrezon/jradio/blob/master/src/test/java/ru/r2cloud/jradio/jpeg/validator/JpegValidatorTest.java), который проходит успешно. Проблема в том, что тест всегда проходит успешно. Несмотря на то, что, теоретически, DC коэффициенты или AC коэффициенты могут быть не найдены, на практике они всегда есть. Даже совсем сломанная картинка не вызывает подозрений. Надо придумывать что-нибудь ещё.

## Заглядывая в будущее

Следующий алгоритм, который я придумал, выглядит так:

 * искать кусочки в следующих 10 минут
 * если впереди обнаружен кусочек, у которого индекс уже найден, то сравнить байты изображения с уже найденными.
 * если они одинаковые, значит это - дубликат
 * а если не одинаковые, значит это - кусочек из следующего изображения
 * удалить все дубликаты в следующих 30 минутах
 
![](img/8.jpg)

И опять неудача. Дело в том, что очень часто самые первые кусочки изображения содержат космос (чёрный пречёрный). А значит, они одинаковые среди нескольких разных изображений. Вот досада.

## Группировка по станциям

Следующей идеей была группировка по станции. Что, если не смешивать кусочки с разных станций, а группировать по станциям и сортировать по времени? Лучше всего идею иллюстрирует следующая диаграмма:

{{< svg "img/9.svg" >}}

В рамках одной станции все кусочки можно отсортировать по времени и выделить изображения. После этого, можно пройтись по всем изображением каждой станции и поискать похожие в других. Если в другой станции есть изображение примерно в это же время, и кусочки совпадают, то это два одинаковых. А если это два одинаковых, то можно слить их вместе и [попытаться восстановить пропущенные](https://github.com/dernasherbrezon/jradio/blob/e1fee09309be55714c3c1988c700a02cd472f4f6/src/test/java/ru/r2cloud/jradio/kunspf/ProcessHistoricalData.java#L134).

![](img/10.jpg)

Уже лучше, но всё равно большие изображения не восстановить. Во-первых, нужно около 1000 кусочков. А во-вторых, даже в рамках одной станции кусочки могут быть перемешаны во времени. У меня нет внятного объяснения этому, кроме того, что база данных асинхронно записывает данные.

## Хоть какие-то результаты

Большие изображения восстановить не получилось. Зато получилось восстановить много маленьких! Если их соединить, то получится небольшое видео с орбиты:

![](img/11.gif)

А вот пример изображений снятых с одной и той же выдержкой. Можно заметить, что, чем больше тёмного космоса в кадре, тем ярче становится Земля.

![](img/12.gif)