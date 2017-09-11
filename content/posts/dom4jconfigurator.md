---
title: "Log4j DOMConfigurator"
date: 2012-10-11T15:14:18+01:00
draft: false
---
DOMConfigurator не поддерживает подстановку свойств при реконфигурации. Будьте бдительны!

Use case:

  1. Конфигурация по умолчанию с использованием ```log4j.configuration``` параметра
  2. Получение свойств и проставление через ```System.setProperty()```
  3. ```DOMConfigurator.configure(System.getProperty("log4j.configuration"))```

