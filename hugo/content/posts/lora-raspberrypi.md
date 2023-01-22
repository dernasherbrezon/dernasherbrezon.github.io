---
title: "sx127x для RaspberryPI"
date: 2023-01-15T12:59:18+00:00
draft: false
tags:
  - c
  - lora
  - raspberrypi
---
Продолжая работать над новой [библиотекой sx127x](https://github.com/dernasherbrezon/sx127x), я решил добавить поддержку Linux и RaspberryPI в частности. Помимо чисто практической надобности, мне хотелось понять насколько отличается программирование под микроконтроллеры от обычных операционных систем.

Я с самого начала спроектировал библиотеку достаточно хорошо, поэтому для миграции под Linux потребовалось совсем немного изменений:

 * отказаться от esp_err.h и сделать возвращаемые коды типа ```int```
 * вынести работут с SPI в отдельный заголовок и переопределить для разных платформ
 
Если первый пункт достаточно простой, то со вторым пришлось повозиться.

## SPI в Linux

В современных версиях ядра Linux (4.x+) есть поддержка SPI. На стороне операционной системы есть драйвер, который создаёт устройства вида ```/dev/spidevX.X``` для работы из пользовательского режима. Каждое мастер-устройство может иметь от одного до несколько SPI шин. Каждая шина состоит из нескольких проводов: MOSI, MISO, SCLK, SS. К каждой шине может подключаться до несколько slave устройств.

{{< svg "/img/lora-raspberrypi/3.svg" >}}

В RaspberryPI по-умолчанию включена только одна SPI шина SPI0. У неё адрес ```/dev/spidev0.X```. При желании можно включить и вторую шину в файле ```/boot/config.txt```:

```
dtoverlay=spi1-3cs
```

К каждой шине RaspberryPI можно подключить до двух slave устройств.

![](/img/lora-raspberrypi/1.png)

Таким образом получается, что SPI драйвер создаст 4 файла:

 * /dev/spidev0.0
 * /dev/spidev0.1
 * /dev/spidev1.0
 * /dev/spidev1.1
 
Если в ESP32 при инициализации SPI нужно было явно прописывать какой пин отвечает за какой сигнал, то в RaspberryPI достаточно открыть нужное устройство для работы:

```c
int spi_device_fd = open("/dev/spidev0.0", O_RDWR);
if (spi_device_fd < 0) {
    perror("unable to open device");
    return EXIT_FAILURE;
}
```

А далее уже конфигурировать, используя ioctl:


```c
int mode = SPI_MODE_0; // CPOL=0, CPHA=0
LINUX_ERROR_CHECK(ioctl(spi_device_fd, SPI_IOC_WR_MODE, &mode));
```

API для отправки и получения данных выглядит очень похоже на ESP32:

```c
struct spi_ioc_transfer tr[2];
memset(&tr, 0, sizeof(tr));
tr[0].tx_buf = (unsigned long)&reg;
tr[0].len = 1;
tr[1].rx_buf = (unsigned long)result;
tr[1].len = data_length;
int code = ioctl(*(int *)spi_device, SPI_IOC_MESSAGE(2), &tr);
```

Для этого используется структура ```spi_ioc_transfer``` и всё тот же ioctl. В примере выше показан полудуплексный режим работы: сначала отправляется команда с типом регистра, а потом читается ответ в переменную ```result``` длины ```data_length```. Для полнодуплексного режима нужно было бы использовать всего одно сообщение, в котором были бы заполненны ```tx_buf``` и ```rx_buf```. Однако, для управления sx127x достаточно полудуплексного режима.
 
## GPIO в Linux

В принципе, одного SPI достаточно, чтобы работать с sx127x. Для того, чтобы получить сообщение, нужно было бы периодически вызывать функцию ```sx127x_handle_interrupt```. Она проверяет выставлен ли флаг полученного сообщения и вызывает нужный обработчик. Однако, если сообщения приходят часто или через заранее неизвестные интервалы, то при таком способе можно пропустить пакет. Каждый новый будет перезатирать предыдущий во внутренней памяти чипа. Чтобы этого избежать, нужно использовать прерывания. В sx127x есть целых 6 пинов, которые генерируют различные типы прерываний. Для отправки и получения достаточно подключить только один - DIO0. 

Но как обработать его в Linux?

Для этого нужно использовать gpio драйвер. Это стандартный драйвер, который разграничивает доступ пользователей к пинам устройства и позволяет работать нескольким программам независимо.

В RaspberryPI он создаёт устройство ```/dev/gpiochip0```. Его нужно открыть, чтобы начать работу:

```c
int fd = open("/dev/gpiochip0", O_RDONLY);
if (fd < 0) {
    perror("unable to open device");
    return EXIT_FAILURE;
}
```

Далее зарезервировать один из пинов или "линию" в терминологии Linux:

```c
struct gpioevent_request rq;
rq.lineoffset = 27;
rq.eventflags = GPIOEVENT_EVENT_RISING_EDGE;
char label[] = "lora_raspberry";
memcpy(rq.consumer_label, label, sizeof(label));
rq.handleflags = GPIOHANDLE_REQUEST_INPUT;
int code = ioctl(fd, GPIO_GET_LINEEVENT_IOCTL, &rq);
```

В примере выше я резервирую пин 27 для получения событий. Событие в данном случае это изменение состояния с "низкий уровень" на "высокий уровень". Это именно то, что будет делать чип при генерации прерывания.

После этого необходимо ожидать событие с помощью poll API:

```c
struct pollfd pfd;
pfd.fd = rq.fd;
pfd.events = POLLIN;
fprintf(stdout, "waiting for packets...\n");
while (1) {
    code = poll(&pfd, 1, GPIO_POLL_TIMEOUT);
    if (code < 0) {
        perror("unable to receive gpio interrupt");
        break;
    } else if (pfd.events & POLLIN) {
        sx127x_handle_interrupt(device);
    }
}
close(rq.fd);
```

Если событие получено, то вызывать функцию-обработчик прерывания ```sx127x_handle_interrupt```.

## Сборка

Пару слов нужно сказать о сборке проекта. Из-за того, что API для SPI отличается между ESP32 и Linux, мне пришлось вынести весь код, работающий с SPI в отдельный файл ```sx127x_spi.h```. В нём есть 4 метода следующего вида, которые имплементированы по разному для разных платформ:

```c
/**
 * @brief Read up to 4 bytes from device via SPI
 * 
 * @param reg Register
 * @param spi_device Pointer to variable to hold the device handle. Can be different on different platforms
 * @param data_length Number of bytes to read into result
 * @param result Where the data will be written to
 * @return 
 *         - SX127X_ERR_INVALID_ARG   if parameter is invalid
 *         - SX127X_OK                on success
 */
int sx127x_spi_read_registers(int reg, void *spi_device, size_t data_length, uint32_t *result);
```

Во время сборки под RaspberryPI я компилирую ```sx127x_linux_spi.c```, а для ESP32 - ```sx127x_esp_spi.c```.

## Тестирование

Для тестирования я купил модуль RA-02. Он содержит внутри себя чип sx1278. Пришлось немного попаять, чтобы в результате получилось что-то вроде этого:

![](/img/lora-raspberrypi/2.png)

В своём тесте я передавал сигнал с ESP32 на другой ESP32 и RaspberryPI. Всё сработало идеально, за исключением расчёта ошибки частоты. sx127x чип может вычислить разницу между частотой на которой было получено сообщение и частотой, на которую был настроен приёмник. В случае с ESP32 он выдавал около -473 Гц, а для RaspberryPI около 4024 Гц. Скорее всего это объясняется тем, что кристаллы-генераторы несущей частоты немного отличаются для двух модулей.