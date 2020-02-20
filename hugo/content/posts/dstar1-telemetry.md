---
title: "Декодирование телеметрии D-STAR ONE"
date: 2020-02-19T14:14:18+01:00
draft: false
cover: /img/dstar1-telemetry/4.png
tags:
  - java
  - satellite
  - спутники
  - mobitex
---
Я уже давно декодирую телеметрию с D-STAR ONE, но совсем недавно, просматривая логи базовой станции, наткнулся на следующую ошибку:

```
unable to parse beacon
java.io.EOFException
        at java.base/java.io.DataInputStream.readUnsignedByte(DataInputStream.java:295)
        at ru.r2cloud.jradio.dstar1.PayloadData.<init>(PayloadData.java:102)
        at ru.r2cloud.jradio.dstar1.Dstar1Beacon.readBeacon(Dstar1Beacon.java:27)
        at ru.r2cloud.jradio.Beacon.readExternal(Beacon.java:16)
```

Эта случайная ошибка в логах и моя любознательность стали причиной интересного расследования, которое значительно улучшило качество приёма телеметрии.

## Расследование

Как обычно в таких случаях, я скачал сырые данные и попытался воспроизвести ошибку локально. Код ```Dstar1Beacon``` достаточно простой, поэтому остановившись в дебаг-режиме, я сразу понял в чём дело. ```CMX909bBeacon``` декодирует данные и возвращает массив байт, который и будет использоваться в дальнейшем. 

```java
DataInputStream dis = ...
byte[] dataFromBlocks = CMX909bBeacon.readDataBlocks(NUMBER_OF_BLOCKS, randomizer, dis);
if (dataFromBlocks != null) {
	payload = new PayloadData(dataFromBlocks);
}
```

Сам же ```CMX909bBeacon``` выглядит следующим образом:

```java
public static byte[] readDataBlocks(int numberOfBlocks, MobitexRandomizer randomizer, DataInputStream dis) throws IOException, UncorrectableException {
	ByteArrayOutputStream baos = new ByteArrayOutputStream();
	for (int i = 0; i < numberOfBlocks; i++) {
		try {
			byte[] block = readDatablock(randomizer, dis, BLOCK_SIZE_BYTES);
			baos.write(block);
		} catch (UncorrectableException e) {
			// if some data recovered, then return it
			// at least some SourcePacket might be recovered
			if (baos.size() > 0) {
				return baos.toByteArray();
			} else {
				// if this is the first block and we cannot recover it
				// then throw Exception. most likely whole packet is invalid
				throw e;
			}
		}
	}
	return baos.toByteArray();
}
```

Для каждого блока (о них чуть ниже), происходит декодирование и добавление в результирующий массив. Самая интересная часть находится в обработке ```UncorrectableException```. Если блок не удалось декодировать, то возвращаются только успешно декодированные данные. Но если декодированных данных нет, то ```UncorrectableException``` пробрасывается дальше.

Видимо, из-за этого как раз и возник ```EOFException```. Из метода вернулось неполное количество байт, и ```PayloadData``` просто не смог десериализоваться.

С причиной всё понятно, но как же правильно исправить эту ошибку? Для этого нужно вспомнить структуру протокола Mobitex.

![](/img/dstar1-telemetry/1.png)

Фрейм состоит из шапки и нескольких блоков данных. Каждый блок данных кодируется независимо от других. D-STAR ONE передаёт фиксированное количество блоков - 6.

При декодировании каждого блока происходит коррекция ошибок и проверка контрольной суммы. Этого достаточно, чтобы однозначно сказать корректные данные получены или нет. Самое важное заключается в том, что все блоки кодируются независимо. Например, обычно фрейм кодируется следующим образом: сначала идут данные, потом идёт контрольная сумма, а потом коды коррекции ошибок. Если не удалось сделать коррекцию ошибок или контрольная сумма не совпала, то весь фрейм просто отбрасывается.

![](/img/dstar1-telemetry/2.jpg)

В Mobitex каждый блок кодируется независимо.

![](/img/dstar1-telemetry/3.jpg)

И если один из блоков не прошёл декодирование, то его можно отбросить. При этом остальные блоки вполне можно восстановить. При этом потеряется только часть данных. Осталось понять, как правильно читать данные из такого массива.

## [GapDataInputStream](https://github.com/dernasherbrezon/jradio/blob/master/src/main/java/ru/r2cloud/jradio/util/GapDataInputStream.java)

Для работы с таким потоком байт обычный массив ```byte[]``` не подходит. Во-первых, он занимает место там, где отсутствуют данные. А во-вторых, нужно явно возвращать пустые значения, если идёт чтение из "дырки". Для этого я создал структуру данных ```GapData``` и поток ```GapDataInputStream```, который очень похож на обычный ```DataInputStream```. Основная его идея достаточно проста: если идёт чтение из "дырки" то нужно возвращать ```null```, в противном случае - число.

![](/img/dstar1-telemetry/4.png)
 
В данном примере, ```short B = null```, потому что один из байтов попадает в дырку. А вот ```byte C``` будет содержать значение. Также я сделал методы очень похожие на ```DataInputStream```: ```readUnsignedByte``` или ```readUnsignedShort```. Из-за этого миграция на новую структуру данных стала тривиальной:

```java
batteryChargeOut = dis.readUnsignedShort() * 2.5f / (4096 * 20 * 0.033f);
```

Нужно заменить на:
```java
Integer unsignedShort = dis.readUnsignedShort();
if (unsignedShort != null) {
	batteryChargeOut = unsignedShort * 2.5f / (4096 * 20 * 0.033f);
}
```

При этом все внутренние поля должны измениться на объекты ```float -> Float```, ```byte -> Byte``` и так далее.

## Послесловие

Судя по коду ```CMX909bBeacon``` я уже догадывался, что можно частично прочитать данные. Однако, я забыл добавить правильную обработку в десериализатор. Теперь же, с помощью ```GapDataInputStream``` я смогу получать больше ценной информации с орбиты земли.