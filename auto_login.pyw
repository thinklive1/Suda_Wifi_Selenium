import json
import os
import shutil
import sys
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import Select
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.service import Service as ChromeService

# 运营商映射关系
CARRIER_MAP = {
    "@xyw": "校园网",
    "@zgyd": "中国移动",
    "@cucc": "中国联通",
    "@ctc": "中国电信",
}
CONFIG_FILENAME = "suda_wifi_config.json"


def load_login_config() -> tuple[str, str, str, str]:
    """Load the active carrier and its dedicated credentials from JSON."""
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), CONFIG_FILENAME)
    try:
        with open(config_path, "r", encoding="utf-8") as config_file:
            config = json.load(config_file)
    except FileNotFoundError as error:
        raise RuntimeError(
            f"未找到配置文件: {config_path}。请参考 suda_wifi_config.example.json 创建它。"
        ) from error
    except json.JSONDecodeError as error:
        raise RuntimeError(f"配置文件 JSON 格式错误: {config_path}; {error}") from error

    if not isinstance(config, dict):
        raise RuntimeError("配置文件根节点必须是 JSON 对象。")

    carrier = str(config.get("active_carrier", "")).strip()
    accounts = config.get("accounts")
    if carrier not in CARRIER_MAP.values():
        supported_carriers = "、".join(CARRIER_MAP.values())
        raise RuntimeError(
            f"配置项 active_carrier 必须是以下运营商之一: {supported_carriers}；当前值: {carrier!r}"
        )
    if not isinstance(accounts, dict):
        raise RuntimeError("配置项 accounts 必须是包含各运营商账号密码的对象。")

    account = accounts.get(carrier)
    if not isinstance(account, dict):
        raise RuntimeError(f"accounts 中缺少当前运营商“{carrier}”的账号密码配置。")

    username = str(account.get("username", "")).strip()
    password = str(account.get("password", ""))
    if not username:
        raise RuntimeError(f"accounts.{carrier}.username 不能为空。")
    if not password:
        raise RuntimeError(f"accounts.{carrier}.password 不能为空。")

    return username, password, carrier, next(
        value for value, name in CARRIER_MAP.items() if name == carrier
    )


def create_chrome_driver(options: webdriver.ChromeOptions) -> webdriver.Chrome:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    local_driver = os.path.join(script_dir, "chromedriver.exe")
    path_candidates = [local_driver, shutil.which("chromedriver")]
    # log_path = os.path.join(script_dir, "chromedriver.log")

    for candidate in path_candidates:
        if candidate and os.path.exists(candidate):
            print(f"使用本地 ChromeDriver: {candidate}")
            # service = ChromeService(executable_path=candidate, log_path=log_path)
            service = ChromeService(executable_path=candidate)
            return webdriver.Chrome(service=service, options=options)

    print("未找到本地 chromedriver，尝试使用 Selenium 内置驱动管理器...")
    # service = ChromeService(log_path=log_path)
    service = ChromeService()
    return webdriver.Chrome(service=service, options=options)


def pause_between_actions():
    time.sleep(2)


# def dump_debug_info(driver: webdriver.Chrome, stage: str) -> None:
#     script_dir = os.path.dirname(os.path.abspath(__file__))
#     try:
#         print(f"[调试] 阶段: {stage}")
#         print(f"[调试] URL: {driver.current_url}")
#         print(f"[调试] 标题: {driver.title}")
#         try:
#             user_agent = driver.execute_script("return navigator.userAgent")
#             print(f"[调试] UA: {user_agent}")
#         except Exception as e:
#             print(f"[调试] 读取UA失败: {e}")
#
#         timestamp = time.strftime("%Y%m%d_%H%M%S")
#         screenshot_path = os.path.join(script_dir, f"debug_{stage}_{timestamp}.png")
#         html_path = os.path.join(script_dir, f"debug_{stage}_{timestamp}.html")
#         try:
#             driver.save_screenshot(screenshot_path)
#             print(f"[调试] 截图已保存: {screenshot_path}")
#         except Exception as e:
#             print(f"[调试] 截图失败: {e}")
#         try:
#             with open(html_path, "w", encoding="utf-8") as file:
#                 file.write(driver.page_source)
#             print(f"[调试] 页面源码已保存: {html_path}")
#         except Exception as e:
#             print(f"[调试] 页面源码保存失败: {e}")
#     except Exception as e:
#         print(f"[调试] dump_debug_info 失败: {e}")


def wait_for_network_ok(driver: webdriver.Chrome, max_wait_seconds: int = 30) -> None:
    start_time = time.monotonic()
    last_error = None
    while time.monotonic() - start_time < max_wait_seconds:
        try:
            page_source = driver.page_source
            if (
                "ERR_NETWORK_CHANGED" not in page_source
                and "您的连接已中断" not in page_source
            ):
                return
            last_error = "ERR_NETWORK_CHANGED"
            print("检测到网络变更页面，尝试重新加载...")
            driver.refresh()
            pause_between_actions()
        except Exception as e:
            last_error = str(e)
        time.sleep(2)
    raise RuntimeError(f"网络未稳定，最后错误: {last_error}")


def login(username: str, password: str, carrier_name: str, carrier_value: str):
    try:
        select_element = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.NAME, "ISP_select"))
        )

        # 创建 Select 对象
        select = Select(select_element)

        # 选择指定的选项
        select.select_by_value(carrier_value)
        pause_between_actions()

        print(f"已选择运营商: {carrier_name}")

        username_input = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located(
                (By.CSS_SELECTOR, "input[placeholder='用户名']")
            )
        )
        username_input.clear()  # 清空输入框
        pause_between_actions()
        username_input.send_keys(username)
        pause_between_actions()
        print("已输入用户名")

        pasword_input = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located(
                (By.CSS_SELECTOR, "input[placeholder='密码']")
            )
        )

        # 输入用户名
        pasword_input.clear()  # 清空输入框
        pause_between_actions()
        pasword_input.send_keys(password)
        pause_between_actions()
        print("已输入密码")

        login_button = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.XPATH, "//input[@value='登录']"))
        )
        login_button.click()
        pause_between_actions()
        print("已进行登录")

    except Exception as e:
        print(f"登录出现错误：{e}")


def logout():
    try:
        # 等待注销按钮可见，并点击
        logout_button = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.NAME, "logout"))
        )
        logout_button.click()
        pause_between_actions()
        print("注销按钮已点击。")
        confirm_button = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.CLASS_NAME, "boxy-btn1"))
        )
        confirm_button.click()
        pause_between_actions()
        back_button = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.NAME, "GobackButton"))
        )
        back_button.click()
        pause_between_actions()
        print("返回登录页")
    except Exception as e:
        print(f"注销出现错误：{e}")


if __name__ == "__main__":
    # 清理代理环境变量，避免驱动下载/握手经过错误代理导致 SSL 失败
    for proxy_key in [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "http_proxy",
        "https_proxy",
        "ALL_PROXY",
        "all_proxy",
    ]:
        os.environ.pop(proxy_key, None)
    os.environ["NO_PROXY"] = "*"
    try:
        username, password, carrier_name, carrier_value = load_login_config()
        print(f"已加载配置文件，运营商: {carrier_name}")
    except Exception as e:
        print(f"配置加载失败: {e}")
        sys.exit(1)

    options = webdriver.ChromeOptions()
    options.add_argument("--headless=new")
    options.add_argument("--ignore-certificate-errors")
    options.add_argument("--ignore-ssl-errors")
    options.add_argument("--no-proxy-server")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=1280,720")
    options.add_argument("--disable-proxy-for-http")
    options.add_argument("--disable-ssl-session-cache")
    options.add_argument("--disable-offline-auto-reload")
    prefs = {
        "profile.default_content_setting_values.notifications": 2,
        "profile.managed_default_content_settings.images": 2,
    }
    options.add_experimental_option("prefs", prefs)
    options.add_experimental_option("excludeSwitches", ["enable-logging"])

    try:
        driver = create_chrome_driver(options)
        # try:
        #     caps = driver.capabilities
        #     browser_version = caps.get("browserVersion")
        #     driver_version = (
        #         caps.get("chrome", {}).get("chromedriverVersion")
        #         if isinstance(caps.get("chrome"), dict)
        #         else None
        #     )
        #     print(f"[调试] Chrome版本: {browser_version}")
        #     if driver_version:
        #         print(f"[调试] ChromeDriver版本: {driver_version}")
        # except Exception as e:
        #     print(f"[调试] 读取版本信息失败: {e}")
    except Exception as e:
        print(f"浏览器驱动初始化失败: {e}")
        print(
            "建议：把 chromedriver.exe 放到脚本目录，或确认网络可访问 Chrome 驱动下载源。"
        )
        sys.exit(1)

    try:
        # 添加重试机制处理 SSL 错误
        max_retries = 3
        for attempt in range(max_retries):
            try:
                driver.get("http://10.9.1.3")
                pause_between_actions()
                wait_for_network_ok(driver, max_wait_seconds=30)
                break
            except Exception as e:
                if attempt < max_retries - 1:
                    print(f"连接失败 (尝试 {attempt + 1}/{max_retries}): {e}")
                    import time

                    time.sleep(2**attempt)  # 指数退避
                else:
                    raise

        login_button = WebDriverWait(driver, 2).until(
            EC.presence_of_element_located((By.XPATH, "//input[@value='登录']"))
        )
        if login_button:
            login(username, password, carrier_name, carrier_value)
            print("进行退出")
            driver.quit()
            sys.exit()
        else:
            print("已经登陆,不执行操作")
            driver.quit()
            sys.exit()
    except Exception as e:
        print(f"出现错误,未执行任何操作。: {e}")
        # try:
        #     dump_debug_info(driver, "main_error")
        # except Exception as dump_error:
        #     print(f"[调试] 采集调试信息失败: {dump_error}")
        try:
            driver.quit()
        except:
            pass
        sys.exit(1)
