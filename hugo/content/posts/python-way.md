---
title: "Жемчужины Python кода"
date: 2020-09-23T22:01:18+01:00
draft: false
tags:
  - разработка
---

В своих статьях я стараюсь рассказывать о небольших технологических штуках и проблемах, с которыми периодически сталкиваюсь. Но вот недавно я столкнулся с [совершенно замечательным кодом](https://github.com/ralent/swampsat2/blob/ee011be72626cc6e63803d14dc775ca675cbcc6d/lib/swampsat2.py#L447), написанным на Python, и не могу пройти мимо, чтобы не покритиковать. Итак, есть вот такая функция:

```python
def getkbits8(num, k, p):
    binary = bin(num)[2:]  # convert number into binary first
    leadingzeros = 8 - len(binary)  # Count the necessary leading zeros to fill byte
    binary = '0' * leadingzeros + binary  # Fill byte with leading zeros
    end = 8 - p - 1
    start = end - k + 1
    k_bit_sub_str = binary[start: end + 1]  # extract k  bit sub-string
    return int(k_bit_sub_str, 2)  # convert extracted sub-string into decimal again
```

Она используется следующим образом:

```python
frequentlock = ParseDownlink._parsebinary(hexarray, 'uint8')  # Get whole register
ordict['vutrx_rx_frequentlock'] = getkbits8(frequentlock, 1, 0)  # Split register by bit position
```

На вход подаётся беззнаковый байт, некий индекс К и ещё один индекс Р. На выходе получается число. Я, признаюсь честно, не знаю Python и поэтому потратил много времени, чтобы понять как работает эта функция. К слову сказать, мне нужно было переписать парсер для телеметрии Swampsat2 с Python на Java для своего проекта.

Итак, что же делает эта функция на самом деле? Ответ:

```java
int frequentlock = dis.readUnsignedByte();
rxFrequentlock = ((frequentlock >> 0) & 0x1);
```

Эта функция всего-навсего выделяет биты из байта. Если нужно получить 4 старших бита, то нужно вызвать функцию вот так:

```python
getkbits8(frequentlock, 4, 4)
```

Работает это так:

 * число конвертируется в строку. Например: ```bin(3)``` -> ```'0b11'```
 * берётся строка. В моём примере - это '11'
 * спереди дописывается необходимое количество нулей. Так, чтобы длина стала равна 8. Это длина байта в битах.
 * выделяется подстрока нужного размера
 * она конвертируется в число и возвращается

Я не первый раз вижу настолько плохой код и поэтому оправился от шока достаточно быстро. Тем не менее, меня всё не покидала мысль о мотивации программиста, который это писал. Предположим, что этот код писал новичок, и он, банально, не знал, что такое битовые операции. Но это не сходится с тем, что использованы сложные операции работы с массивами и строками. Неужели понять битовые операции было сложнее?

Второй вопрос, который я себе задал: зависит ли плохой код от языка программирования? Этот код написан на Python, и автор с лёгкостью и простым синтаксисом смог описать сложные операции. Чтобы ответить на этот вопрос, я надел перчатки и написал этот же код, но на Java:

```java
private static int getkbits8(int num, int k, int p) {
	String binary = Integer.toBinaryString(num);
	int leadingzeros = 8 - binary.length();
	StringBuilder zeros = new StringBuilder();
	for (int i = 0; i < leadingzeros; i++) {
		zeros.append('0');
	}
	binary = zeros.toString() + binary;
	int end = 8 - p - 1;
	int start = end - k + 1;
	String k_bit_sub_str = binary.substring(start, end + 1);
	return Integer.parseInt(k_bit_sub_str, 2);
}
```

Если честно, то версия на Java кажется более громоздкой. И это хорошо. Если новичок задумает написать такую функцию, то он несколько раз подумает нет ли способа попроще. Этот пример лишний раз убеждает меня в том, что многословность Java, на самом деле, большой плюс. Весь Java код буквально кричит о том, что происходит выделение ресурсов и неэффективные операции, а также видно, что процессор будет выполнять странные вещи. В Python же достаточно написать ```'0' * leadingzeros```.

Надеюсь, автор оригинального Python кода всего лишь проходил стажировку и не писал софт для настоящих спутников.

