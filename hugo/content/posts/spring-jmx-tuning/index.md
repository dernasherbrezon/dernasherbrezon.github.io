---
title: "Оптимизация spring jmx"
date: 2011-12-11T13:14:18+01:00
draft: false
tags:
  - java
  - Spring
  - производительность
---
Spring по умолчанию позволяет настроить экспорт бинов в jmx. Сделано это через удобные аннотации @ManagedResource. Однако существует сценарий при котором поведение по умолчанию не совсем подходит. Рассмотрим этот случай:

  * spring context лениво инициализируется. Очень удобно если есть некоторый db-context.xml в котором описаны все Datasource. Соответственно инициализируются только те которые используются. Также очень удобно при ограниченных ресурсах. fail-fast + старт только необходимого.
  * org.springframework.jmx.export.MBeanExporter умеет инициализировать JMX бины для ленивых spring бинов. Как это происходит: если spring бин - лениво инициализируется, то создаётся proxy через cglib который и будет jmx бином. При первом обращении к его методам/аттрибутам происходит инициализация spring бина.
  
Проблема:

  * возможна инициализация ненужных соединений. Список бинов содержит все возможные jmx бины.
  
Решение:

  * Необходимо создать BeanPostProcessor для контроля уже проинициализированных бинов. 
  
Например:
  
	import java.util.ArrayList;  
	import java.util.List;  
	  
	import org.springframework.beans.BeansException;  
	import org.springframework.beans.factory.config.BeanPostProcessor;  
	  
	public class StartedBeansAwarePostProcessor implements BeanPostProcessor {  
	  
	 private final List<String> beanNames = new ArrayList<String>();  
	  
	 @Override  
	 public Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {  
	  return bean;  
	 }  
	  
	 @Override  
	 public Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {  
	  beanNames.add(beanName);  
	  return bean;  
	 }  
	   
	 public boolean isStarted(String beanName) {  
	  return beanNames.contains(beanName);  
	 }  
	  
	} 
	
После этого необходимо создать свой Assembler. Например:

	import org.springframework.beans.factory.annotation.Required;  
	import org.springframework.jmx.export.assembler.MetadataMBeanInfoAssembler;  
	import org.springframework.jmx.support.JmxUtils;  
	  
	public class LazyAssembler extends MetadataMBeanInfoAssembler {  
	  
	 private StartedBeansAwarePostProcessor startedBeans;  
	  
	 @Override  
	 public boolean includeBean(Class beanClass, String beanName) {  
	  if (startedBeans.isStarted(beanName)) {  
	   if (isMBean(beanClass)) {  
	    return true;  
	   }  
	   return super.includeBean(beanClass, beanName);  
	  }  
	  return false;  
	 }  
	  
	 @Required  
	 public void setStartedBeans(StartedBeansAwarePostProcessor startedBeans) {  
	  this.startedBeans = startedBeans;  
	 }  
	  
	 private boolean isMBean(Class beanClass) {  
	  return JmxUtils.isMBean(beanClass);  
	 }  
	  
	} 
	
И сконфигурировать spring контекст:

	<bean id="lazyAssembler" class="LazyAssembler" p:attributeSource-ref="jmxAttributeSource">  
	 <property name="startedBeans" ref="startedBeanAwarePostProcessor" />  
	</bean>  
	<bean id="startedBeanAwarePostProcessor" class="StartedBeansAwarePostProcessor" />  
	<bean name="mbeanServer" class="org.springframework.jmx.support.MBeanServerFactoryBean" p:locateExistingServerIfPossible="true" />  
	<bean id="jmxAttributeSource" class="org.springframework.jmx.export.annotation.AnnotationJmxAttributeSource" />  
	<bean id="mbeanExporter" class="org.springframework.jmx.export.MBeanExporter"  
	 p:server-ref="mbeanServer">  
	 <property name="assembler" ref="lazyAssembler" />  
	 <property name="autodetectMode" value="2" />  
	 <property name="namingStrategy">  
	  <bean class="org.springframework.jmx.export.naming.MetadataNamingStrategy">  
	   <property name="attributeSource" ref="jmxAttributeSource" />  
	   <property name="defaultDomain" value="domain" />  
	  </bean>  
	 </property>  
	</bean> 
	
Особое внимание на параметр: autodetectMode. Он должен обязательно быть равен 2, иначе MBeanExporter будет игнорировать Assembler при принятии решении о том включать бин или нет. Теперь можно инициализировать контекст. Например:

	ctx.getBean(SomeBean.class); //инициализация корневого бина. По зависимостям должна инициализировать все бины необходимые для работы приложения. StartedBeansAwarePostProcessor запоминает все проинициализированные бины.  
	ctx.getBean("mbeanExporter"); //инициализация jmx бинов. Выполнять строго после инициализации всех бинов приложения.
