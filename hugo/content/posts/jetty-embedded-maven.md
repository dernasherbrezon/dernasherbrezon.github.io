---
title: "Запуск Jetty Embedded через spring"
date: 2010-11-11T13:14:18+01:00
draft: false
tags:
  - java
  - maven
  - jetty
  - spring
---
Для начала необходимо добавить зависимости в pom.xml:

	<dependency>  
	 <groupId>org.eclipse.jetty</groupId>  
	 <artifactId>jetty-server</artifactId>  
	 <version>7.2.0.RC0</version>  
	 <exclusions>  
	  <exclusion>  
	   <groupId>org.mortbay.jetty</groupId>  
	   <artifactId>test-jndi-webapp</artifactId>  
	  </exclusion>  
	  <exclusion>  
	   <groupId>org.mortbay.jetty</groupId>  
	   <artifactId>test-annotation-webapp</artifactId>  
	  </exclusion>  
	  <exclusion>  
	   <groupId>org.mortbay.jetty</groupId>  
	   <artifactId>test-jaas-webapp</artifactId>  
	  </exclusion>  
	  <exclusion>  
	   <groupId>org.mortbay.jetty</groupId>  
	   <artifactId>example-async-rest-webapp</artifactId>  
	  </exclusion>  
	 </exclusions>  
	</dependency>  
	<dependency>  
	 <groupId>org.eclipse.jetty</groupId>  
	 <artifactId>jetty-servlet</artifactId>  
	 <version>7.2.0.RC0</version>  
	</dependency>  
	      <dependency>  
	          <groupId>org.eclipse.jetty</groupId>  
	          <artifactId>jetty-jsp-2.1</artifactId>  
	          <version>7.2.0.RC0</version>  
	      </dependency>    
	      <dependency>  
	          <groupId>org.eclipse.jetty</groupId>  
	          <artifactId>jetty-webapp</artifactId>  
	          <version>7.2.0.RC0</version>  
	      </dependency>    
	<dependency>  
	 <groupId>org.springframework</groupId>  
	 <artifactId>spring-core</artifactId>  
	 <version>3.0.1.RELEASE</version>  
	</dependency>  
	<dependency>  
	 <groupId>org.springframework</groupId>  
	 <artifactId>spring-context</artifactId>  
	 <version>3.0.1.RELEASE</version>  
	</dependency>  
	<dependency>  
	 <groupId>org.springframework</groupId>  
	 <artifactId>spring-web</artifactId>  
	 <version>3.0.1.RELEASE</version>  
	</dependency>  
	<dependency>  
	 <groupId>org.springframework</groupId>  
	 <artifactId>spring-webmvc</artifactId>  
	 <version>3.0.1.RELEASE</version>  
	</dependency>

Затем в ```main-class``` указать:

	Server server = new Server(9090);  
	ServletHolder holder = new ServletHolder(new DispatcherServlet());  
	holder.setName("root");  
	WebAppContext webappContext = new WebAppContext("src/main/webapp/", "/");  
	webappContext.addServlet(holder, "*.do");  
	server.setHandler(webappContext);  
	server.start();  
	server.join();

После этого создать WEB-INF/root-servlet.xml:

	<?xml version="1.0" encoding="UTF-8"?>  
	<beans  xmlns="http://www.springframework.org/schema/beans"   
	        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"   
	        xmlns:mvc="http://www.springframework.org/schema/mvc"  
	        xmlns:context="http://www.springframework.org/schema/context"  
	       xsi:schemaLocation="http://www.springframework.org/schema/beans   
	                           http://www.springframework.org/schema/beans/spring-beans.xsd  
	                           http://www.springframework.org/schema/context   
	                           http://www.springframework.org/schema/context/spring-context.xsd  
	                           http://www.springframework.org/schema/mvc  
	                           http://www.springframework.org/schema/mvc/spring-mvc.xsd">  
	  
	  
	    <context:component-scan base-package="com.my.package" />  
	    <mvc:annotation-driven />  
	  
	</beans> 
