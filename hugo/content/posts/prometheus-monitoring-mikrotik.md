---
title: "Мониторинг Mikrotik роутеров с помощью Prometheus"
date: 2021-08-07T06:50:18+01:00
cover: /img/prometheus-monitoring-mikrotik/grafana.png
draft: false
tags:
  - monitoring
  - администрирование
  - memory
  - prometheus
---
Для начала вообще пара слов о том, зачем мониторить роутеры. Роутер, как и любое другое устройство, имеет аппаратные ресурсы, которые могут закончится. Например, браузер стал медленнее открывать страницы или видео стало медленнее загружаться. Это может быть как из-за провайдера, так и из-за роутера. Возможно, к роутеру подключено слишком много устройств, и он стал медленнее, или параллельно кто-то качает слишком много - всё это может быть причиной замедления.

Большинство роутеров позволяют посмотреть загруженность ЦПУ или памяти прямо в админке. Но это лишь статичная информация, которая может и не дать полной картины происходящего. Гораздо удобнее смотреть изменение различных покателей во времени. Например, ЦПУ загружен на 80% - это хорошо и плохо? Если на графике видно, что загрузка ЦПУ совпадает с уменьшением скорости скачивания, то да, дело в ЦПУ. А если 80% загрузка держится последние несколько дней или недель, то вряд ли она связана со скоростью скачивания. Возможно, что-то ещё могло повлиять.

## Общая схема

В качестве роутера я использовал [Mikrotik waP R](https://mikrotik.com/product/RBwAPR-2nD). Он позволяет использовать SIM карту, чтобы подключиться к сотовой сети, и раздавать Wi-Fi.

![mikrotik_wap_r](/img/prometheus-monitoring-mikrotik/mikrotik_wap_r.jpg)

Общая схема мониторинга выглядит следующим образом:

![](/img/prometheus-monitoring-mikrotik/schema.png)

## Mikrotik

Prometheus не может напрямую читать метрики из Mikrotik. Вместо этого он обращается в специальный exporter, который выдаёт метрики в нужном формате. Mikrotik позволяет экспортировать метрики с помощью протокола [SNMP](https://ru.wikipedia.org/wiki/SNMP). По-умолчанию он не включён. Его можно включить следующей командой:

```
[admin@MikroTik] /snmp
[admin@MikroTik] /snmp>  set enabled yes
```

## SNMP-exporter

[SNMP-exporter](https://github.com/prometheus/snmp_exporter) нужен для того, чтобы преобразовать метрики из SNMP формата в специальный формат, который понимает Prometheus. Устанавливается он достаточно просто:

```
wget https://github.com/prometheus/snmp_exporter/releases/download/v0.20.0/snmp_exporter-0.20.0.linux-armv7.tar.gz
tar xzf snmp_exporter-0.20.0.linux-armv7.tar.gz
```

Следующим шагом будет создание systemd сервиса, который бы автоматически стартовал на старте. Для этого нужно создать следующий файл:

```
sudo vi /etc/systemd/system/snmp_exporter.service
```

Файл:

```
[Unit]
Description=SNMP Exporter
After=network-online.target

[Service]
User=pi
Restart=on-failure
ExecStart=/usr/local/bin/snmp_exporter --config.file='<path to>/snmp_exporter-0.20.0.linux-armv7/snmp.yml'

[Install]
WantedBy=multi-user.target
```

Нужно только внимательно указать путь к snmp.yml файлу. Этот файл содержит маппинг SNMP объектов на метрики Prometheus для разных типов устройств. Mikrotik уже есть в этом файле, так что можно использовать его как-есть.

Дальше необходимо скопировать snmp_exporter:

```
sudo cp ./snmp_exporter-0.20.0.linux-armv7/snmp_exporter /usr/local/bin/snmp_exporter
```

После этого стартовать сервис:

```
sudo systemctl enable snmp_exporter
sudo systemctl start snmp_exporter
```

Проверить статус сервиса можно командой:

```
sudo systemctl status snmp_exporter
```

Если сервис стартовал успешно, то вывод будет следующий:

![](/img/prometheus-monitoring-mikrotik/snmp_exporter.png)


## Prometheus

Все метрики будут сохраняться в [Prometheus](https://prometheus.io). Prometheus - это специальная база данных для хранения метрик. Его можно запустить локально, либо в облаке. 

Я не буду подробно описывать как настроить и стартовать Prometheus. Есть достаточно [полная инструкция](https://prometheus.io/docs/prometheus/latest/getting_started/) как это сделать.

Сейчас же достаточно настроить подключение к exporter. Это делается через основной конфиг prometheus.yaml:

```yaml
  - job_name: mikrotik
    static_configs:
      - targets:
        - 192.168.1.1  # SNMP device.
    metrics_path: /snmp
    params:
      module: [mikrotik]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: raspberrypi.local:9116
```

## Grafana

Можно воспользоваться [готовыми дашбордами](https://grafana.com/grafana/dashboards/14420) и сразу импортировать их в Grafana.

![](/img/prometheus-monitoring-mikrotik/image.png)

Однако, каждое устройство немного отличается друг от друга и большинство дашбордов ничего не покажет. Для [Mikrotik waP R](https://mikrotik.com/product/RBwAPR-2nD) я выбрал самые важные параметры:

 * Uptime - ```sysUpTime{instance='$instance'}/100```
 * Load CPU - ```avg(hrProcessorLoad{instance='$instance'})```
 * Load RAM - ```(hrStorageUsed{hrStorageIndex='65536',instance='$instance'} * 100 )/(hrStorageSize{hrStorageIndex='65536',instance='$instance'})```
 * Load system disk - ```(hrStorageUsed{hrStorageIndex='131072',instance='$instance'} * 100 )/(hrStorageSize{hrStorageIndex='131072',instance='$instance'})```
 * In/Out bit/sec - ```irate(ifHCInOctets{job='mikrotik',ifName=~'$Interface',instance='$instance'}[20s])*8```
 * RSRP (Reference Signal Received Power) уровень LTE сигнала - ```mtxrLTEModemSignalRSRP```
 
После чего добавил панели:

![](/img/prometheus-monitoring-mikrotik/grafana.png)

Для того, чтобы добавить другие метрики, нужно сначала найти их oid (идентификатор в SNMP):

```
[admin@MikroTik] /interface lte print oid
```

После этого необходимо найти oid в snmp.yaml:

```
pi@rasp-buster:~ $ grep 1.3.6.1.4.1.14988.1.1.16.1.1.4 snmp.yml -B 1
  - name: mtxrLTEModemSignalRSRP
    oid: 1.3.6.1.4.1.14988.1.1.16.1.1.4
```

Метрика с именем ```mtxrLTEModemSignalRSRP``` должна быть доступна в Prometheus.
