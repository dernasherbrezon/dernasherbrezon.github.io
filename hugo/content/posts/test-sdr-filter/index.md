---
title: "Тестирование SDR Filter v1.1"
date: 2019-08-08T19:20:18+01:00
draft: false
tags:
  - rtlsdr
  - тестирование
  - фильтры
---

Одна из моих базовых станций принимает очень много помех. Из-за [низкой чувствительности]({{< ref "/dynamic-range" >}}) rtl-sdr, полезный сигнал почти нельзя получить. У меня возникла идея о том, что часть помех может приходить от USB разъёма RPi. Чтобы проверить эту идею, я недавно приобрёл SDR Filter v1.1 от компании ExpElectroLab и решил сделать на него небольшое видео ревью.

{{< youtube 7n8nLey6yYo >}}

## Процесс тестирования

Самое интересное началось сразу же после распаковки устройства. Дело в том, что входящий USB порт формата Type B. Поэтому просто подключить последовательно фильтр и rtl-sdr к компьютеру не получится. В комплекте устройства USB переходника нет, поэтому пришлось идти в ближайший магазин и покупать дополнительный кабель.

После подключения выясняется, что устройство не работает.

Я измерил напряжение на входящем и исходящем USB портах. На входе 4.7В, а на выходе 3.2В. Видимо стандартного напряжения компьютера недостаточно. Но на всякий случай я спросил у авторов, в чём же может быть проблема. Оказывается, надо покупать более короткий шнур. Это первое USB устройство на моей памяти, которое работает в зависимости от длины шнура. На сайте производителя об этом не сказано.

![](img/description.png)


Мне пришлось заказать ещё один шнур, на этот раз покороче. После подключения, загорелась лампочка, но rtl-sdr по-прежнему не определялся. На этот раз напряжение на выходном USB порту было 3.5В. По-прежнему недостаточно. Я связался с автором ещё раз и попросил помощи. Автор посоветовал закоротить диод D1. У меня дома нет паяльника, поэтому я не могу проверить это решение.

## Выводы

 1. SDR Filter явно имеет проблемы с питанием. Непонятно как авторы тестировали его.
 2. Мне не удалось заставить его работать, поэтому он теперь просто валяется в коробке.

