---
title: "Изображения с DSLWP-B"
date: 2020-02-15T15:40:18+01:00
draft: false
cover: /img/aistechsat-3/aistechsat-3.jpg
tags:
  - java
  - ssdv
  - jpeg
---

[Недавно](https://destevez.net/2019/12/dslwp-b-whole-mission-telemetry/) Дэниел и команда DSLWP выложили в общий доступ данные со спутника [DSLWP-B](http://dk3wn.info/blog/satelliten/dslwp/). Эти данные включают в себя телеметрию, а также [изображения Луны и Земли](http://lilacsat.hit.edu.cn/dashboard/pages_en/pics-b.html). Сам спутник уже был штатно разбит о Луну, поэтому больше данных с него не будет. Мне же стало интересно, как передавались изображения с лунной орбиты. Плюс, это была бы отличная возможность проверить работу моего [ssdv](https://github.com/dernasherbrezon/ssdv4j) декодера.

![](/img/dslwp-b-images/1.png)

Для начала я скачал [dslwp-data](https://github.com/tammojan/dslwp-data) репозиторий и попытался декодировать файлы *.ssdv. Эти файлы уже содержат фреймы SSDV в специфичном для DSLWP протоколе. Как обычно, для экономии канала, разработчики немного изменили [этот протокол]({{< ref "/decoding-jy1sat" >}}): нет полей ```Packet Type```, ```Callsign``` и ```FEC```.

Я [написал](https://github.com/dernasherbrezon/jradio/blob/master/src/main/java/ru/r2cloud/jradio/dslwp/DslwpSsdvPacketSource.java) небольшую обёртку, которая преобразует специфичные для DSLWP SSDV пакеты в стандартные. Однако, с первого раза ничего не получилось. Оказывается, для кодирования изображений использовалась цветовая субдискретизация 2х1 и она была просто сломана в ssdv4j.

Я переписал чудовищные циклы с хитрыми индексами:

```java
for (int row = 0; row < DataUnitDecoder.PIXELS_PER_DU; row++) {
	for (int col = 0; col < DataUnitDecoder.PIXELS_PER_DU; col++) {
		int cbCrSourceIndex = row * DataUnitDecoder.PIXELS_PER_DU + col;
		for (int subRow = 0; subRow < yComponent.getMaxRows(); subRow++) {
			for (int subCol = 0; subCol < yComponent.getMaxCols(); subCol++) {
				int ySourceIndex = row * DataUnitDecoder.PIXELS_PER_DU * yComponent.getMaxCols() * yComponent.getMaxRows() + subRow * DataUnitDecoder.PIXELS_PER_DU * yComponent.getMaxCols() + col * yComponent.getMaxCols() + subCol;
				rgb[ySourceIndex] = convertToRgb(yComponent.getBuffer()[ySourceIndex], cbComponent.getBuffer()[cbCrSourceIndex], crComponent.getBuffer()[cbCrSourceIndex]);
			}
		}
	}
}
```

На чуть более простые:

```java
int[] cbCrIndexMapping = getSrcIndexMapping(yComponent.getSubsamplingMode());
for (int row = 0; row < yComponent.getMaxRows() * DataUnitDecoder.PIXELS_PER_DU; row++) {
	for (int col = 0; col < yComponent.getMaxCols() * DataUnitDecoder.PIXELS_PER_DU; col++) {
		int sourceIndex = row * yComponent.getMaxCols() * DataUnitDecoder.PIXELS_PER_DU + col;
		rgb[sourceIndex] = convertToRgb(yComponent.getBuffer()[sourceIndex], cbComponent.getBuffer()[cbCrIndexMapping[sourceIndex]], crComponent.getBuffer()[cbCrIndexMapping[sourceIndex]]);
	}
}
```

Исправил несколько ошибок. И в целом, не было ничего сложного, кроме разных хитрых индексов. Единственную странность я обнаружил в спецификации SSDV. В каждом пакете есть такие поля как ```Width``` и ```Height``` измеряемые в количестве MCU. Чтобы получить высоту в пикселах, логично умножить ```Width``` на высоту одного MCU. Тут есть засада. В зависимости от цветовой субдискретизации высота MCU может быть как 8 пикселей (для 2x1), так и 16 (для 2x2). Поэтому для получения высоты картинки при 2x1 я просто умножал высоту на 8. Однако, это не сработало. Похоже MCU в SSDV понимается как блок пикселей 16х16. И совсем не совпадает с тем, что написано в стандарте jpeg. Сделав правильные выводы, я получил картинку:

![](/img/dslwp-b-images/dslwp-137.png)

Если же сравнивать мой декодер с официальным, то мне нравится больше мой. Он правильнее обрабатывает пропущенные пакеты и всегда выдаёт чёрный цвет.

![](/img/dslwp-b-images/compare.png)

После того, как я обработал все существующие пакеты, удалось найти несколько хороших кадров и сделать анимацию:

![](/img/dslwp-b-images/gif.gif)

На ней отлично видно, как спутник облетает Луну, и то, как Земля вращается на заднем плане.