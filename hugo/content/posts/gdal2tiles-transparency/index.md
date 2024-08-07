---
title: "Ошибки прозрачности в gdal2tiles"
date: 2020-05-07T22:21:18+01:00
draft: false
tags:
  - geotiff
  - gdal
  - r2weather
---


В своей работе над [r2weather.ru](https://r2weather.ru) я нахожу множество багов. Иногда они случаются по собственной глупости, а иногда появляются в самых неожиданных местах. Причём, ошибки связаны не только с программированием и различными алгоритмами, но и со странным поведением внешних систем.

Из недавнего, я обнаружил на результирующей карте совершенно странные полупрозрачные полоски толщиной один-два пиксела.

![](img/41.png)

Выглядит это, прямо скажем, не очень. Особенно на большой карте мира.

## Исследование

Вообще, я специально конвертирую jpeg-файл, принимаемый со спутника в формат .png. Во-первых, это формат без потерь. То есть, каждый пиксел, который я вижу в результирующем jpeg, выглядит именно так, как он был передан со спутника. Это очень сильно улучшает изображение, так как нет двойного перекодирования в jpeg. Во-вторых, png поддерживает альфа-канал. Если часть изображения не была принята, то в альфа-канал можно поместить полностью прозрачные пикселы. Они будут нести дополнительную информацию и их можно будет красиво "не показать" на карте.

Если ещё раз глянуть на получившийся тайл, то видно, что полупрозрачные пикселы находятся по краям изображения. Если бы я не принял часть пакетов со спутника, то у меня была бы полоса шириной 8 пикселов. А это значит, что эти пикселы добавляются где-то во время обработки.

Чтобы их найти, достаточно проверить изображение на каждом шаге обработки.

![](img/1.png)

GeoTIFF получается с очень чёткими краями.

![](img/2.png)

Ага! Попался. gdal2tiles создаёт тайлы с полупрозрачными пикселами по краям. И это очень странно:

 1. В [официальной документации](https://gdal.org/programs/gdal2tiles.html) об этом нигде не сказано
 2. Полупрозрачность добавляется не во всех слоях! В примере выше тайл с 5-го уровня, а для уровня 6 никакой прозрачности не добавляется.
 
![](img/3.png)

Исправляется эта ошибка достаточно просто. Во-первых, при отрисовке нужно брать изображения чуть-чуть внахлёст. Тогда будет плавный переход между двумя изображениями. А во-вторых можно игнорировать все пикселы в которых выставлена полупрозрачность.

```java
for (int i = 0; i < sourceImage.getWidth(); i++) {
	for (int j = 0; j < sourceImage.getHeight(); j++) {
		int sourceRgb = sourceImage.getRGB(i, j);
		// do not override dest with no data
		// do not copy any partially tranparent pixels
		// gdal2tiles.py create them on the edges for some reason
		if ((sourceRgb >>> 24) != 0xFF) {
			continue;
		}
		destImage.setRGB(i, j, sourceRgb);
	}
}
```

## Результат

Такое небольшое изменение дало на удивление хорошие результаты.

![](img/4.png)

На изображении выше наложены два пролёта подряд на Северной Америкой. Несмотря, на то, что границы каждого пролёта немного размыты, изображение склеено вполне неплохо.