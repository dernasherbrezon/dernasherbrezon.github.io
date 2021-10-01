---
title: "Оптимизация spring-mvc"
date: 2011-11-11T13:14:18+01:00
draft: false
tags:
  - java
  - spring
  - производительность
---
Общие решения всегда медленнее частных. Ниже я собираюсь немного оптимизировать spring-mvc. Оптимизация прежде всего рассчитана на уменьшение генерируемого мусора. Прежде чем начать оптимизировать надо определиться какие функции фреймворка можно выкинуть и какими фичами пренебречь:

  * ISO-8859-1-encoded URLs. Человеко-понятные-урл (ЧПУ) используются SEO продвижения в поисковых движках. Но что если это не нужно? Зачем на каждый запрос тратить процессорное время и память?
  * Всегда абсолютные пути для сервлетов-контроллёров. По умолчанию spring-mvc позволяет использовать относительные пути для include запросов. При оптимизации выполненной ниже и использовании Jetty результат такой же. Возможно это актуально для других контейнеров.
  * Не использовать jstl. Достаточно спорное предположение, однако кто то может не использовать jstl и писать на обычных JSP. Я не знаю jstl. И пишу <% %>.
  
Итак первая достаточно безболезненная оптимизация не требующая никаких жертв: выключить publishEvent в DispatcherServlet. По умолчанию он отправляет в ApplicationContext сообщение о времени обработки запроса. В production зачастую уже поздно что то мерить. Делается это в web.xml:

```xml
<init-param>  
	<param-name>publishEvents</param-name>  
	<param-value>false</param-value>  
</init-param>
```

Избавиться от @RequestMapping. Это очень удобно передавать @Param напрямую в метод. Однако реализация AnnotationMethodHandlerAdapter в spring-mvc достаточно требовательна к ресурсам и генерирует кучу мусора на каждый запрос. Логичнее было бы сделать найденные методы кешируемыми, но согласно https://jira.springsource.org/browse/SPR-6151 разработчики считают сложным пофиксить. Поэтому для простоты и небольшого увеличения скорости сделаем новый контроллёр:

```java
public interface FastController {  
  
    String handleRequest(HttpServletRequest request, HttpServletResponse response) throws Exception;  
      
    String getRequestMappingURL();  

}
```

Чем он лучше чем org.springframework.web.servlet.mvc.Controller? Он позволяет задавать url в том же месте где и содержится его реализация. Не нужно делать лишних движений чтобы добавить его в spring.xml. Соответственно необходимо определить классы которые будут его использовать:

```java
public class FastUrlDetector extends AbstractDetectingUrlHandlerMapping {  
  
      
    public FastUrlDetector() {  
        setAlwaysUseFullPath(true);  
        setUrlDecode(false);  
    }  
      
    @Override  
    protected String[] determineUrlsForHandler(String beanName) {  
        ApplicationContext context = getApplicationContext();  
        Class<?> handlerType = context.getType(beanName);  
        if (FastController.class.isAssignableFrom(handlerType)) {  
            FastController controller = (FastController) context.getBean(beanName);  
            String result = controller.getRequestMappingURL();  
            if (result == null) {  
                throw new IllegalArgumentException("controller doesnt have url mapping: " + beanName);  
            }  
            if( result.isEmpty() ) {  
                throw new IllegalArgumentException("controller doesnt have url mapping: " + beanName);  
            }  
            if( !result.startsWith("/") ) {  
                throw new IllegalArgumentException("only absolute urls are required. Beanname: " + beanName + " Url: " + result);  
            }  
            return new String[]{result};  
        }  
        return null;  
    }  
  
}  
  
public class FastMethodHandlerAdapter implements HandlerAdapter {  
  
    public boolean supports(Object handler) {  
        return (handler instanceof FastController);  
    }  
  
    public ModelAndView handle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {  
        return new ModelAndView(((FastController) handler).handleRequest(request, response));  
    }  
  
    public long getLastModified(HttpServletRequest request, Object handler) {  
 if (handler instanceof LastModified) {  
  return ((LastModified) handler).getLastModified(request);  
 }  
        return -1;  
    }  
  
}
```

Они практически не генерируют мусора. Убрать new ModelAndView не получится не переписав DispatcherServlet. Тем более генерация ModelAndView занимает небольшой процент мусора генерируемого при каждом запросе. После этого необходимо добавить Adapter и Decoder в spring.xml чтобы они автоматически подцеплялись DispatcherServlet при поиске контроллёров.

```xml
<bean class="FastMethodHandlerAdapter"/>  
<bean class="FastUrlDetector" />  
```

Далее. Следующим большим местом которое генерирует много мусора является Renderer. Я не знаю как работает jstl и почему spring-mvc делает множество приседаний для его работы. Поэтому я просто выкинул JstlView (которое используется по умолчанию для .jsp) и заменил его на:

```java
public class FastJSPView extends AbstractUrlBasedView {  
  
    @Override  
    protected void renderMergedOutputModel(Map<String, Object> model, HttpServletRequest request, HttpServletResponse response) throws Exception {  
        RequestDispatcher rd = request.getRequestDispatcher(getUrl());  
        if (useInclude(request, response)) {  
            response.setContentType(getContentType());  
            if (logger.isDebugEnabled()) {  
                logger.debug("Including resource [" + getUrl() + "] in InternalResourceView '" + getBeanName() + "'");  
            }  
            rd.include(request, response);  
        }  
  
        else {  
            if (logger.isDebugEnabled()) {  
                logger.debug("Forwarding to resource [" + getUrl() + "] in InternalResourceView '" + getBeanName() + "'");  
            }  
            rd.forward(request, response);  
        }          
    }  
      
    protected boolean useInclude(HttpServletRequest request, HttpServletResponse response) {  
        return (WebUtils.isIncludeRequest(request) || response.isCommitted());  
    }  
  
}  
  
public class FastJSPViewResolver extends UrlBasedViewResolver {  
  
    public FastJSPViewResolver() {  
        setViewClass(FastJSPView.class);  
    }  
      
}  
```

Часть кода в FastJSPView скопирована с JstlView. И соответственно необходимо добавить в spring.xml:

```xml
<bean id="viewResolver"  
 class="com.st.FastJSPViewResolver">  
 <property name="prefix">  
  <value>/WEB-INF/pages/</value>  
 </property>  
 <property name="suffix">  
  <value>.jsp</value>  
 </property>  
</bean> 
```

Чтобы проверить что есть некоторые улучшения ниже приведён тестовый контроллер который перенаправляет запрос в jsp:

```java
@Controller  
public class FastServlet implements FastController {  
  
    public String handleRequest(HttpServletRequest request, HttpServletResponse response) throws Exception {  
        return "index2";  
    }  
      
    public String getRequestMappingURL() {  
        return "/test2";  
    }  
      
} 
```

Аннотация @Controller используется для автоматического поиска контроллёра в classpath при старте приложения. В результате под нагрузкой jmeter (50 пользователей) получаются следующие показатели:

  * Настройки GC по умолчанию. Оптимизированная версия ~3 коллекции в секунду, неоптимизированная ~6 коллекций
  * Latency & throughtput одинаковые для обоих версий.
  * Время работы HandlerAdapter.handle (от общего времени обработки запроса): для оптимизированной версии 0%, неоптимизированной 31%. Результат впечатляющий. Очевидно это связано с тем что вызов метода напрямую быстрее поиска метода по аанотации и вызова через Reflection
  * Время работы для DispatcherServlet.getLastModified: для оптимизированной версии 0%, неоптимизированной 11%. Связано с тем что AbstractHandlerMapping.getHandler использует абсолютные пути и не использует DefaultAnnotationHandlerMapping.
  * Среднее количество генерируемых объектов в минуту: для оптимизированной версии 4к-5к, неоптимизированной 9к-14к. Уменьшение в 2 раза!
  
Дополнительные находки:

  * ServletRequestAttributes. Не очень удачная абстракция. На каждый запрос создаётся этот объект. Не совсем понятно зачем он нужен когда обычный HTTPServletRequest предоставляет методы setAttribute и getAttribute и пр.
  * Не очень удачная имплементация некоторых объектов в Jetty: Response.setLocale, Request.getRequestDispatcher, Dispatcher.forward. После оптимизации они стали теми местами которые генерируют наибольшее количество мусора. Не совсем понятно зачем им генерировать много объектов, также непонятно почему они не кешируют результаты вычислений.
  * при использовании for each генерируется итератор, который превращается в мусор. Настольные microbenchmark'и показали что итерация по ArrayList при использовании простых индексов быстрее в два раза.
  
Выводы:

  * чем больше слоёв абстракции и "упрощений", тем медленнее обработка.
  * текущие технологии есть куда оптимизировать.
  * нужно хорошо понимать что можно оптимизировать а что нет 
    