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
3. 对比较近的版本应该不需要手动下载浏览器驱动即driver,开着梯子运行一次就会自动下载，这里放一个[chormedriver](https://googlechromelabs.github.io/chrome-for-testing/)链接,本py文件是基于chorme的，用其他浏览器需要微调(不会的话问问ai)
4. 打开项目中的`auto_login.pyw`,把username(学号),password(密码)填成自己的,然后运行,例如在windows终端输入`python auto_login.pyw`, 这步可能稍微会有点麻烦，例如涉及到python虚拟环境的切换，不会的还是建议问ai
6. 如果想定期运行,可以在windows中注册计划任务,例如设置一个每15分钟的触发器,启动一个bat或者ps1文件,这个bat文件可以形如本仓库中的bat和ps1文件,这里放一个教程[windows用任务计划定时执行powershell脚本](https://www.cnblogs.com/saneri/p/18740324)
7. 对仓库里的bat和ps1, 需要将其中的`%脚本目录%`填为pyw文件的路径, 此外这两个实例文件里使用的是我自己的的python解释器路径(我装在venv虚拟环境里), 需要改成你自己的有相关依赖的python路径
8. 项目中默认是不让弹出浏览器窗口的，这和浏览器驱动的设置项 `my_options.add_argument("--headless") `有关,将py文件改为pyw后缀会让执行时不弹出python窗口(后缀记得在脚本里也要改)

### 对了解编程知识的人

这里简单介绍一下原理,就是通过类名等属性定位前端元素,然后像人类一样点击选择这些按钮,看代码或者直接喂给ai都能很容易地自定义  
ps1文件会ping百度官网看能不能上外网，不能的话就断开重连suda_wifi(虽然不知道什么原理，有时候连着suda_wifi久了会进不去登录页)  
