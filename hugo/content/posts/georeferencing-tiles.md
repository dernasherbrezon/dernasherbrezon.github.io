---
title: "Геокодирование спутниковых снимков: Тайлы"
date: 2020-04-20T20:52:18+01:00
cover: /img/georeferencing-tiles/0.png
draft: false
tags:
  - meteor-m
  - спутники
  - ДЗЗ
  - georeferencing
---

Это финальная статья о том, как геокодировать спутниковые снимки. Здесь я постараюсь описать, а что же делать дальше с полученным GeoTIFF файлом. Если интересно о том, как получить GeoTIFF, то можно почитать предыдущие статьи:

  1. [Введение]({{< ref "/georeferencing-satellite-images" >}})
  2. [Опорные точки]({{< ref "/georeferencing-gcp" >}})
  3. [GeoTIFF]({{< ref "/georeferencing-geotiff" >}})
  4. Тайлы

## QGIS

GeoTIFF, полученный на предыдущем шаге выглядит правдоподобно, но хочется убедиться, что проекция выполнена правильно. Самый простой способ - это наложить файл на настоящую карту. Для этого достаточно взять [бесплатную QGIS](https://www.qgis.org/en/site/) и добавить слой OpenStreetMap:

![](/img/georeferencing-tiles/1.png)

После этого добавить слой из GeoTIFF файла:

![](/img/georeferencing-tiles/2.png)

Такое отображение не слишком полезно, поэтому нужно добавить прозрачности. В свойствах слоя нужно сделать общую прозрачность процентов на 60% и проставить "No Data Value = 0".

![](/img/georeferencing-tiles/3.png)

Выглядит значительно лучше, но видно, что изображение совсем не совпадает с картой. В моём примере разница примерно 34км. Это достаточно много.

![](/img/georeferencing-tiles/4.png)

## Ошибки геокодирования

Причин, по котором изображение может не совпадать с картой, множество:

 1. Ошибки модели SGP4
 2. Неправильно выбранная проекция лучей камеры на Землю
 3. Неправильно посчитанные кватернионы
 4. Неправильная ориентация самого спутника на орбите
 5. Неизвестный фактор
 
Каждая из этих причин может вносить существенную ошибку в геокодировании. И для разных спутников решение может быть совершенно разным. В случае Метеор-М2, я заметил, что в одной из работ указывается стандартное значение крена 2.5 градуса. Это значит, что камера спутника не точно смотрит в надир, а под небольшим углом. Я попытался смоделировать это в Rugged:

```java
LOSBuilder losBuilder = new LOSBuilder(rawDirs);
losBuilder.addTransform(new FixedRotation("fixed-rotation", Vector3D.PLUS_I, FastMath.toRadians(2.5)));
TimeDependentLOS lineOfSight = losBuilder.build();
```

Пересоздав GeoTIFF, я получил следующее:

![](/img/georeferencing-tiles/5.png)

Разница составила около 10км. Это значительно лучше, чем было в прошлый раз. Видимо, я на правильном пути. Немножко "поиграв" с углами крена и тангажа, я высчитал их для снимка как 2.6 и 0.6:

```java
LOSBuilder losBuilder = new LOSBuilder(rawDirs);
losBuilder.addTransform(new FixedRotation("fixed-rotation", Vector3D.PLUS_I, FastMath.toRadians(2.6)));
losBuilder.addTransform(new FixedRotation("fixed-rotation", Vector3D.PLUS_J, FastMath.toRadians(0.6)));
TimeDependentLOS lineOfSight = losBuilder.build();
```

В результате даёт:

![](/img/georeferencing-tiles/6.png)

## Тайлы

Изображение идеально совпадает с картой. Что же ещё можно сделать? Рассказать об этом другим! Самый простой способ - это разрезать изображение на тайлы и наложить на одну из известных карт.

В GDAL есть встроенная программа gdal2tiles. С её помощью можно достаточно просто сгенерировать тайлы:

```bash
python3 gdal2tiles.py --profile=mercator -z 3-6 output.tif tiles
```

Эта команда создаст в папке ```tiles``` необходимые тайлы с уровнями детализации 3,4,5,6. Более детальные тайлы не имеет смысла создавать, так как разрешение МСУ-МР километр на пиксель.

После того, как созданы тайлы, их можно загружать на карту (да, снизу карта и её можно двигать и зумить):

<!-- Leaflet -->
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.6.0/dist/leaflet.css"
   integrity="sha512-xwE/Az9zrjBIphAcBb3F6JVqxf46+CDLwfLMHloNu6KEQCAWi6HcDUbeOfBIptF7tcCzusKFjFw2yuvEpDL9wQ=="
   crossorigin=""/>
<script src="https://unpkg.com/leaflet@1.6.0/dist/leaflet.js"
   integrity="sha512-gZwIG9x3wUXg2hdXF6+rVkLF/0Vi9U8D2Ntg4Ga5I5BZpVkVxlJWbSQtXPSiUTtC0TjtGOmxa1AJPuV0CPthew=="
   crossorigin=""></script>

<div id="map" style="height: 480px;"></div>

<script>

// Map
var map = L.map('map', {
    center: [42.1061323234332, 40.66492877632462],
    zoom: 5,
    minZoom: 3,
    maxZoom: 6
});

L.tileLayer('http://{s}.tile.osm.org/{z}/{x}/{y}.png', {attribution: '&copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors', minZoom: 3, maxZoom: 6}).addTo(map);
L.tileLayer('/img/georeferencing-tiles/{z}/{x}/{y}.png', { tms: true, opacity: 0.7, attribution: "", minZoom: 3, maxZoom: 6}).addTo(map);

</script>

## Послесловие

Несмотря на кажущуюся простоту, для меня весь процесс получения картинки со спутника и наложение её на карту, занял два года. В течении этого времени были и радость открытия и полное отрицание получившихся результатов. Но я очень горд тем, что прошёл весь путь. Ведь я смог разобраться в нескольких совершенно не связанных областях знаний и добиться финального результата.

Но я не собираюсь стоять на месте. Есть множество вещей, которые можно улучшить:

 1. Более точное геокодирование на основе береговых линий. Дело в том, что спутник может незначительно менять направление камеры на Землю. Гарантировать значения 2.6 и 0.6 нельзя, поэтому нужно сделать "доводку" изображения.
 2. Нужно создать сервис, который бы собирал изображения с Метеор-М2 и мог бы накладывать их на карту в реальном времени. Это вполне возможно, и я планирую этим заняться в ближайшее время. 
