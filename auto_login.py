import selenium
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import Select
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.firefox.options import Options

# 运营商映射关系
CARRIER_MAP = {
    "@xyw": "校园网",
    "@zgyd": "中国移动",
    "@cucc": "中国联通",
    "@ctc": "中国电信"
}
username = "学号"
password= "密码"

def login():
    try:
        select_element = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.NAME, "ISP_select"))
        )
        
        # 创建 Select 对象
        select = Select(select_element)
        
        # 选择指定的选项
        select.select_by_value("@cucc")  # 通过值选择
        
        print(f"已选择选项")

        username_input = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.CSS_SELECTOR, "input[placeholder='用户名']"))
        )
        username_input.clear()  # 清空输入框
        username_input.send_keys(username)
        print(f"已输入用户名: {username}")

        pasword_input = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.CSS_SELECTOR, "input[placeholder='密码']"))
        )
        
        # 输入用户名
        pasword_input.clear()  # 清空输入框
        pasword_input.send_keys(password)

        login_button = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.XPATH, "//input[@value='登录']"))
        )
        login_button.click()

    except Exception as e:
        print(f"登录出现错误：{e}")


def logout(): 
    try:
        # 等待注销按钮可见，并点击
        logout_button = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.NAME, "logout"))
        )
        logout_button.click()
        print("注销按钮已点击。")
        confirm_button = WebDriverWait(driver, 10).until(
                EC.visibility_of_element_located((By.CLASS_NAME, "boxy-btn1"))
            )
        confirm_button.click()
        back_button = WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.NAME, "GobackButton"))
        )
        back_button.click()
        print("返回登录页")
    except Exception as e:
        print(f"注销出现错误：{e}")

if __name__ == "__main__":
    
    my_options = Options()
    my_options.add_argument("--headless") 
    driver = webdriver.Chrome(options=my_options)
    driver.get("http://10.9.1.3")

    try:
        login_button = WebDriverWait(driver, 3).until(
            EC.presence_of_element_located((By.XPATH, "//input[@value='登录']"))
        )
        if login_button:
            login()
        else:
            print("已经登陆,不执行操作")
            driver.quit()
    except Exception:
        print("登录按钮未找到，未执行任何操作。")


