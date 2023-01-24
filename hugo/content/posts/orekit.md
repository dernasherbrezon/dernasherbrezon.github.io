---
title: "Работа с Orekit"
date: 2020-03-28T10:05:18+01:00
draft: false
cover: /img/orekit/1.png
tags:
  - java
  - orekit
  - спутники
---

Совсем недавно я обнаружил программу [LicenseFinder](https://github.com/pivotal/LicenseFinder). Она позволяет сканировать проект и найти все лицензии, которые используются в зависимостях. Это очень удобно, так как не все лицензии совместимы между собой. Я решил проверить свои open source проекты и обнаружил нестыковку лицензий для [r2cloud](https://github.com/dernasherbrezon/r2cloud). У меня использовалась библиотека [predict4java](https://github.com/g4dpz/predict4java) с лицензией GPL-v2, а у моего проекта лицензия Apache 2.0. Такая зависимость фактически означает, что мой проект тоже должен распространяться под лицензией GPL-v2. И этого мне совсем не хотелось.

Ещё один недостаток predict4java - последний раз значительные изменения были в 2015 году. Да и сама библиотека является портом библиотеки [Predict](http://www.qsl.net/kd2bd/predict.html), которая в свою очередь является портом SGP4 модели, написанной на фортране. 

Я начал искать альтернативы этой библиотеке. А надо сказать, что библиотека очень узкоспециализированная. Она рассчитывает положение спутника относительно Земли на основе модели SGP4. Заменить такую библиотеку это не то же самое, что поменять логирование.

Тем не менее я нашёл достаточно интересную альтернативу - [OreKit](https://www.orekit.org). По заверениям разработчиков, эта библиотека используется в реальных космических миссиях для расчёта орбит. Ещё одним плюсом является то, что она написана на java. Идеально подходит для моего проекта.  

## Настройка

Прежде, чем работать с библиотекой, необходимо её настроить. Здесь всё говорит о том, что это серьёзная программа. Для конфигурации необходимо скачать [orekit-data-master.zip](https://gitlab.orekit.org/orekit/orekit-data/-/archive/master/orekit-data-master.zip). Этот файл содержит множество входных данных для различных математических моделей внутри Orekit. Например, модель Земли и leap second за всё время наблюдений.

После того как файл скачан и распакован в директорию, можно начать работать с библиотекой:

```java
File orekitData = new File("./path/with/orekit-data-master/");
DataProvidersManager manager = DataProvidersManager.getInstance();
manager.addProvider(new DirectoryCrawler(orekitData))
```

## Расчёт пролёта спутника

В моём проекте мне необходимо рассчитать время пролёта над станцией. Как только спутник показывается на горизонте, мне необходимо настроиться на его частоту и записать сигнал. Как только спутник уйдёт за горизонт, мне нужно остановить запись и начать её обрабатывать.

{{< svg "/img/orekit/1.svg" >}}

При этом есть два параметра:

 * гарантированная высота над горизонтом. Спутник может пролетать достаточно далеко от наблюдателя и подниматься лишь на несколько градусов. Иногда этого недостаточно для приёма. Из-за этого необходимо найти все пролёты, при которых спутник поднимается на достаточную высоту.
 * минимальная высота над горизонтом. Как только пролёт найден, необходимо найти начало и конец. Для этого есть минимальная высота.
 
Для начала необходимо описать параметры станции:

```java
GeodeticPoint point = new GeodeticPoint(FastMath.toRadians(latitude), FastMath.toRadians(longitude), 0.0)
Frame earthFrame = FramesFactory.getITRF(IERSConventions.IERS_2010, true);
BodyShape earth = new OneAxisEllipsoid(Constants.WGS84_EARTH_EQUATORIAL_RADIUS, Constants.WGS84_EARTH_FLATTENING, earthFrame);
TopocentricFrame baseStationFrame = new TopocentricFrame(earth, point, "station");
```

После этого создать ```Propagator``` для задания орбиты спутника:

```java
TLEPropagator tlePropagator = TLEPropagator.selectExtrapolator(new TLE("row 1", "row 2"));
```

С помощью него, можно узнать положение спутника в заданное время. Он может работать в 3-х режимах:

 * slave. Приложение само вызывает расчёт координат
 * master. Библиотека вызывает callback-функцию при расчёте
 * ephemeral. Приложение вызывает расчёт координат. При этом время может идти в случайном порядке.
 
Более подробно о режимах можно узнать в [официальной документации](https://www.orekit.org/site-orekit-tutorials-10.1/tutorials/propagation.html). Для расчёта необходимо использовать slave режим и ```ElevationExtremumDetector```. Это специальный фильтр, который будет отфильтровывать только те события, которые имеют максимум высоты.

```java
ElevationExtremumDetector maxDetector = new ElevationExtremumDetector(60, 0.001, baseStationFrame).withMaxIter(48 * 60).withHandler(maxElevationHandler);
tlePropagator.clearEventsDetectors();
tlePropagator.addEventDetector(new EventSlopeFilter<EventDetector>(maxDetector, FilterType.TRIGGER_ONLY_DECREASING_EVENTS));
tlePropagator.setSlaveMode();
tlePropagator.propagate(initialDate, new AbsoluteDate(initialDate, 3600. * 24 * 2));
```

Здесь я создаю такой детектор, который будет рассчитывать высоту относительно ```baseStationFrame``` и вызывать callback ```maxElevationHandler```. Расчёт будет идти с какой-то текущей даты ```initialDate``` и на 2 дня вперёд.

Сам callback выглядит следующим образом:

```java
@Override
public Action eventOccurred(SpacecraftState s, ElevationExtremumDetector detector, boolean increasing) {
	if (FastMath.toDegrees(detector.getElevation(s)) > maxElevation) {
		date = s.getDate();
		return Action.STOP;
	}
	return Action.CONTINUE;
}
```

Если максимальная высота больше гарантированной, то запоминать время и останавливаться. В противном случае продолжать дальше искать.

После того как время с гарантированной высотой найдено, необходимо найти начало и конец пролёта. Для этого используется ```ElevationDetector```.

```java
ElevationDetector boundsDetector = new ElevationDetector(60, 0.001, baseStationFrame).withConstantElevation(FastMath.toRadians(minElevation)).withHandler(minElevationHandler);
tlePropagator.clearEventsDetectors();
tlePropagator.addEventDetector(boundsDetector);
AbsoluteDate startDate = maxElevationHandler.getDate().shiftedBy(-20 * 60.0);
tlePropagator.propagate(startDate, startDate.shiftedBy(40 * 60.));
```

Этот детектор срабатывает, когда спутник поднимается выше минимальной высоты и опускается ниже минимальной.

Обработчик должен выглядеть следующим образом:

```java
@Override
public Action eventOccurred(SpacecraftState s, ElevationDetector detector, boolean increasing) {
	if (increasing) {
		start = s.getDate();
		return Action.CONTINUE;
	}
	end = s.getDate();
	return Action.STOP;
}
```

Он должен запоминать время, если событие "восходящее", то есть высота спутника увеличивается. И запоминать время, если событие "нисходящее".

## Расчёт допплеровского смещения сигнала

Ещё одна вещь, которая необходима в r2cloud - это расчёт смещения допплера для сигнала со спутника. Для этого необходимо рассчитать скорость сближения станции и спутника.

```java
AbsoluteDate date = new AbsoluteDate(new Date(utcTimeMillis), TimeScalesFactory.getUTC());
PVCoordinates currentState = tlePropagator.getPVCoordinates(date);
final double rangeRate = currentLocation.getRangeRate(currentState, tlePropagator.getFrame(), date);
return (long) ((double) freq * (SPEED_OF_LIGHT - rangeRate) / SPEED_OF_LIGHT);
```

Здесь, для переданного времени ```utcTimeMillis``` я высчитываю текущую позицию спутника. Далее нахожу скорость сближения двух тел. После того, как найдена скорость сближения, можно рассчитать частоту.

## Вывод

OreKit - это очень мощная библиотека, с помощью которой можно смодулировать множество разных ситуаций. Правда, порог вхождения в неё достаточно высокий.	
