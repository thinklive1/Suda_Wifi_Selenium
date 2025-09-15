# Suda_Wifi_Selenium

## 这是什么?  

一个自动登录suda wifi的python脚本

## 不是有很多自动登录脚本了吗?

根据我的搜索,github上大部分自动登录脚本都是基于网络请求库,也就是完全基于命令行对suda服务器发送登陆请求,这样的好处是,依赖少,纯命令行环境也能用,而缺点则是一旦苏大更改认证请求标准,就得重新改,而且写和改也较为复杂
本脚本则使用了Selenium(浏览器自动工具,也就是通过脚本像人一样操作浏览器的一个工具),可以模拟人类使用suda wifi登录页,这样的缺点上依赖一个浏览器驱动,配置会麻烦一点,优点则是通用性强,suda一般不会改登录页的前端元素,就是改了重新定位也不难

## 如何使用?

### 对不了解任何编程知识的人

简单地说可以分为几个步骤:

1. 配置python环境,这点可以参考[菜鸟教程](https://www.runoob.com/python3/python3-install.html)
2. 安装[Selenium](https://www.selenium.dev/zh-cn/documentation/webdriver/getting_started/install_library/),其实就是一句`pip install selenium`
3. 下载你的浏览器驱动,driver,例如[chormedriver](https://googlechromelabs.github.io/chrome-for-testing/)
4. 打开项目中的`auto_login.py`,把username(学号),password(密码)填成自己的,然后运行,例如在windows终端输入`python auto_login.py`
5. 如果想定期运行,可以在windows中注册计划任务,例如设置一个每15分钟的触发器,启动一个bat文件,这个bat文件可以形如目录中的[`auto_login.bat`](./auto_login.bat)

### 对了解编程知识的人

这里简单介绍一下原理,就是通过类名等属性定位前端元素,然后像人类一样点击选择这些按钮,看代码或者直接喂给ai都能很容易地自定义



