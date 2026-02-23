# cyberdog_ws

## 项目名称
本项目是基于小米铁蛋四足开发者平台的主要功能包。
## 仓库介绍
该仓库为四足开发平台项目代码主仓库，已将原有的 9 个子仓库合并为单一仓库，直接 clone 即可获取全部代码，无需再执行 `vcs import`。

原始子仓库来源：[MiRoboticsLab/cyberdog_ws](https://github.com/MiRoboticsLab/cyberdog_ws)（rolling 分支）

## 开发者模式解锁（前置条件）

CyberDog 2 出厂默认未开启 SSH 访问，需要先解锁才能进行开发。由于小米官方已停止维护，在线申请解锁已不可用，可通过以下方式手动解锁：

### 方式一：USB 直连 SSH（先试这个）

用 USB 数据线连接电脑与机器狗，尝试直接 SSH：

```bash
ssh mi@192.168.55.1   # 密码 123
```

如果能连上，说明你的机器狗已处于解锁状态，可直接跳到编译章节。

### 方式二：NX 核心板 + 开发套件 + Debug 串口（一定能成功）

如果 USB 直连无法 SSH，则需要通过硬件调试串口进入系统：

1. 拆开机器狗，取出 Jetson Xavier NX 核心板（SOM 模块）
2. 将核心板安装到 NVIDIA Jetson Xavier NX 开发套件（Developer Kit）上
3. 用 USB-TTL 串口转接器连接开发套件上的 Debug UART 串口（TX/RX/GND，3.3V 电平）
4. 电脑端使用串口工具（PuTTY / minicom / MobaXterm），波特率 115200
5. 上电后即可在串口终端看到 Linux 启动日志和 login 提示
6. 用 `mi` / `123` 登录后，手动开启 SSH：

```bash
sudo systemctl enable ssh
sudo systemctl start ssh
```

7. 将核心板装回机器狗后，即可通过 USB 直连 SSH 访问

> **注意**：Debug 串口是硬件级别的调试接口，不受任何软件解锁状态限制，因此一定能成功。

### 方式三：修改开源代码绕过解锁检查（软件方案）

如果已经能 SSH 进入 NX（通过上述任一方式），可以通过修改开源代码彻底消除解锁限制，使系统始终认为已解锁。

**原理**：系统通过闭源工具 `/usr/bin/cyberdog_get_info unlock-state` 查询解锁状态（返回 0 = 未解锁，非 0 = 已解锁）。该工具只在开源代码的两个位置被调用，修改这两处即可。

**修改 1：`unlock_request` 节点**

文件：`manager/unlock_request/include/unlock_request/unlock_request.hpp`（源码中此文件位于 `nx_robot/cyberdog/include/unlock_request/unlock_request.hpp`）

将 `GetUnlockStatus()` 和 `UnlockAccess()` 函数体改为直接返回成功：

```cpp
// 修改前
int GetUnlockStatus()
{
    std::string parament = " unlock-state; echo $?";
    std::string ShellCommand = "/usr/bin/cyberdog_get_info" + parament;
    int result = GetShellCommandResult(ShellCommand);
    return result;
}

// 修改后：始终返回"已解锁"
int GetUnlockStatus()
{
    INFO("GetUnlockStatus() bypassed, always return unlocked");
    return 1;  // 非0 = 已解锁
}
```

```cpp
// 修改前
int UnlockAccess()
{
    std::string parammentKey = "/SDCARD/cyberdog-key; echo $?";
    std::string ShellCommand = "/usr/bin/cyberdog_get_info unlock-request " + parammentKey;
    int result = GetShellCommandResult(ShellCommand);
    return result;
}

// 修改后：始终返回"解锁成功"
int UnlockAccess()
{
    INFO("UnlockAccess() bypassed, always return success");
    return 0;  // 0 = 成功
}
```

**修改 2：OTA 脚本（可选）**

文件：`cyberdog_bringup` 部署后位于 NX 上的 `/opt/ros2/cyberdog/share/cyberdog_ota/scripts/utils/cyberdog_systems.sh`

```bash
# 修改前
function get_not_unlocked()
{
    state=$(sudo /usr/bin/cyberdog_get_info unlock-state | tail -1 | awk '{print $NF}')
    ...
}

# 修改后：始终返回已解锁
function get_not_unlocked()
{
    echo 1  # 非0 = 已解锁
}
```

> **说明**：`/usr/bin/cyberdog_get_info` 是闭源二进制，仅用于解锁状态管理，不影响运动控制、导航、语音等任何实际功能。修改后可选择保留或删除该文件。编译修改后的 `unlock_request` 包并部署到 NX 即可永久生效。

## 编译与部署

### 编译方式：Docker 交叉编译

必须使用小米官方 Docker 镜像编译，镜像中包含 WebRTC 头文件/静态库、galaxy-fds-sdk、gRPC 等闭源或定制依赖，这些在 NX 本地系统上不存在，无法通过 apt 安装。

> **为什么不能在 NX 上直接编译？** 实测 NX 本地编译会因缺少 `/usr/local/include/webrtc_headers/`（WebRTC 开发头文件）、`/usr/local/lib/libwebrtc.a`（静态库）等依赖导致 `image_transmission` 等包无法编译。这些文件只在官方 Docker 镜像的 `docker-depend.tar.gz` 中提供。

官方 Dockerfile 说明：[MiRoboticsLab/blogs - Dockerfile 使用说明](https://github.com/MiRoboticsLab/blogs/blob/rolling/docs/cn/dockerfile_instructions_cn.md)

#### 步骤 1：安装 Docker Desktop（Windows 用户）

1. 下载 Docker Desktop：https://www.docker.com/products/docker-desktop/
2. 运行安装程序，安装时勾选 **"Use WSL 2 instead of Hyper-V"**
3. 安装完成后**重启电脑**
4. 打开 Docker Desktop，等待左下角显示绿色 **"Engine running"**

> Docker Desktop 免费用于个人和教育用途。它内置 WSL2（Windows 的 Linux 子系统），不需要额外安装 VMware 或 Ubuntu。

验证安装（在 PowerShell 中执行）：

```powershell
docker --version
docker run hello-world
```

看到 `Hello from Docker!` 即表示安装成功。

#### 步骤 2：启用 arm64 模拟（qemu）

CyberDog 2 的 NX 是 arm64 架构，而你的电脑是 x86，需要 qemu 来模拟 arm64。
在 PowerShell 中执行：

```powershell
docker run --privileged multiarch/qemu-user-static --reset -p yes
```

此命令只需执行一次（重启电脑后可能需要重新执行）。

#### 步骤 3：制作编译镜像

从官方 Dockerfile 说明页面复制完整的 Dockerfile 内容，保存到本地：

```powershell
# 在你喜欢的位置创建目录
mkdir E:\cyberdog_docker
# 用文本编辑器在该目录下创建名为 Dockerfile 的文件（无扩展名）
# 将官方 Dockerfile 内容粘贴进去
# 内容来源：https://github.com/MiRoboticsLab/blogs/blob/rolling/docs/cn/dockerfile_instructions_cn.md
```

构建镜像（耗时较长，需下载大量依赖）：

```powershell
cd E:\cyberdog_docker
docker build -t cyberdog_build:1.0 .
```

> **注意**：Dockerfile 中的依赖包从 `cnbj2m.fds.api.xiaomi.com` 下载。如遇下载失败（小米服务器可能已关闭），需要自行寻找离线包或从已有 Docker 镜像导出。

镜像关键内容（Dockerfile 第 11 步安装）：
- `/usr/local/include/webrtc_headers/` — WebRTC 头文件（`image_transmission` 需要）
- `/usr/local/lib/libwebrtc.a` — WebRTC 静态库
- `/usr/local/lib/libgalaxy-fds-sdk-cpp.a` — FDS 云存储 SDK
- `/usr/local/lib/` 下的 gRPC 相关库
- Python 3 设为默认（`/usr/bin/python` → `python3`）

#### 步骤 4：启动容器并编译

```powershell
# 启动容器，将本地源码目录映射到容器内
# Windows 路径用 / 分隔，Docker Desktop 会自动转换
docker run --privileged=true -it -v E:/机器狗2/cyberdog2/cyberdog_ws_rolling:/home/builder/cyberdog_ws cyberdog_build:1.0 bash
```

现在你已进入容器（Linux 终端），在容器内执行：

```bash
# 加载 ROS2 环境
source /opt/ros2/galactic/setup.bash

cd /home/builder/cyberdog_ws

# 编译单个包及其依赖（首次编译某个包时用）
colcon build --merge-install --packages-up-to <包名>

# 后续修改同一个包（用 --packages-select，更快）
colcon build --merge-install --packages-select <包名>

# 全量编译所有包
colcon build --merge-install
```

> **提示**：容器关闭后数据不会丢失（因为源码目录是映射的），但容器内临时安装的工具会丢失。如果想保留容器状态，用 `docker commit` 保存。

#### 关于 cyberdog_fds 闭源库（本仓库已修复，无需手动操作）

系统预装的 `cyberdog_common` 导出两个 cmake 目标：
- `cyberdog_log`（开源，本仓库有源码）
- `cyberdog_fds`（闭源，小米 FDS 云存储 SDK 封装）

ROS2 的 overlay 机制使本仓库的 `cyberdog_common` 覆盖系统版，但开源版本没有 `cyberdog_fds`，导致 `motion_manager` 等下游包编译失败。

本仓库已通过手动生成 cmake 导出文件 + `ament_package(CONFIG_EXTRAS)` 注入解决：
1. `install(FILES)` 拷贝系统的 `libcyberdog_fds.so`
2. `file(WRITE cyberdog_fdsExport.cmake)` 手写导出文件定义 IMPORTED 目标
3. `ament_package(CONFIG_EXTRAS)` 注入桥接文件

详见 `utils/cyberdog_common/CMakeLists.txt` 第 61-106 行。

#### 步骤 5：部署到机器狗

```powershell
# ── 在 PowerShell 中：将编译产物推送到 NX ──
# 用 USB 线连接电脑和机器狗
scp -r install/lib/<包名> mi@192.168.55.1:/home/mi/
scp -r install/share/<包名> mi@192.168.55.1:/home/mi/
scp -r install/include/<包名> mi@192.168.55.1:/home/mi/
# 密码 123
```

```bash
# ── SSH 进 NX 替换 ──
ssh mi@192.168.55.1   # 密码 123

# 替换前备份（首次部署时做一次）
sudo cp -r /opt/ros2/cyberdog /SDCARD/cyberdog.bak

# 单包替换（推荐，风险最小）
sudo cp -rf /home/mi/<包名> /opt/ros2/cyberdog/lib/
sudo cp -rf /home/mi/<包名> /opt/ros2/cyberdog/share/
sudo cp -rf /home/mi/<包名> /opt/ros2/cyberdog/include/
sudo rm -rf /home/mi/<包名>

# 重启生效
sudo reboot
```

#### 步骤 6：验证

```bash
ssh mi@192.168.55.1

# 检查节点和话题是否正常
ros2 node list
ros2 topic list

# 确认手机 APP 能正常连接和控制
```

#### 步骤 7：回滚（如果出问题）

```bash
sudo rm -rf /opt/ros2/cyberdog
sudo mv /SDCARD/cyberdog.bak /opt/ros2/cyberdog
sudo reboot
```

## 系统通信架构

CyberDog 2 内部各模块之间的通信方式：

```
                  音频板（独立硬件，自带 CPU + WiFi）
                  功能：唤醒词检测、语音识别（本地/连小爱云端）
                        │
                        │ LCM (UDP 多播)
                        │ audio_cyberdog_topic / cyberdog_audio_topic
                        │
                        ▼
               ┌─────────────────────────────────┐                MR813 运控板
  手机 APP     │     NX (Jetson Xavier NX)       │               ┌──────────────┐
     │         │                                 │  LCM          │ cyberdog_    │
     │ WiFi    │  ROS2 节点：                     │  (UDP 多播)   │  control     │
     │ gRPC    │  · cyberdog_grpc   (APP 通信)    │──────────────►│  (MPC/WBC/RL)│
     └────────►│  · cyberdog_audio  (语音桥接)    │◄──────────────│ manager      │
               │  · motion_manager  (运动管理)    │               │  (系统管理)   │
               │  · motion_action   (LCM 收发)   │               └──────────────┘
               │  · device_manager  (设备管理)    │
               │  · sensor_manager  (传感器管理)  │
               │  · algorithm_manager(算法任务)   │
               └──────────┬──────────┬───────────┘
                          │          │
                  CAN 总线 │          │ BLE 蓝牙
              (embed_protocol)        │
                          │          手机（首次配网）
                          ▼          BLE 遥控器配件
            ┌─────────────────────────────┐
            │  CAN 外设：                    │
            │  BMS（电池） · LED（灯效）      │
            │  TOF（深度） · 超声波           │
            │  UWB（定位） · 电子皮肤         │
            └─────────────────────────────┘
```

所有外部设备（手机、音频板、MR813、CAN 外设）都只与 NX 通信，**NX 是唯一的中枢**。
手机 APP 不能直接访问 MR813，完整链路为：
`手机 APP → gRPC → NX cyberdog_grpc → ROS2 → motion_action → LCM → MR813`

### NX ↔ MR813 运动通信协议（LCM）

NX 和 MR813 之间通过 LCM（UDP 多播）通信，**不是 CAN 总线**。

| LCM 地址 | 通道 | 方向 | 内容 |
|----------|------|------|------|
| `udpm://239.255.76.67:7671` | `robot_control_cmd` | NX→MR813 | 运动指令 |
| `udpm://239.255.76.67:7670` | `robot_control_response` | MR813→NX | 运动状态回报 |
| `udpm://239.255.76.67:7671` | `user_gait_file` | NX→MR813 | 自定义步态文件 |
| `udpm://239.255.76.67:7671` | `user_gait_result` | MR813→NX | 步态定义结果 |
| `udpm://239.255.76.67:7667` | `external_imu` | MR813→NX | IMU 数据 |
| `udpm://239.255.76.67:7667` | `local_heightmap` | MR813→NX | 高程图 |
| `udpm://239.255.76.67:7667` | `global_to_robot` | MR813→NX | 里程计 |
| `udpm://239.255.76.67:7667` | `motor_temperature` | MR813→NX | 电机温度 |
| `udpm://239.255.76.67:7669` | `state_estimator` | MR813→NX | 状态估计器 |

**运动指令结构 `robot_control_cmd_lcmt`**（NX→MR813）：

| 字段 | 类型 | 含义 |
|------|------|------|
| `mode` | int32 | 运动模式 |
| `gait_id` | int32 | 步态 ID |
| `life_count` | int32 | 生命计数（递增，MR813 用来检测通讯断开） |
| `vel_des[3]` | float | 期望速度 [vx, vy, vyaw] |
| `rpy_des[3]` | float | 期望姿态 [roll, pitch, yaw] |
| `pos_des[3]` | float | 期望位置 |
| `step_height[2]` | float | 抬腿高度 [前腿, 后腿] |
| `acc_des[6]` | float | 期望加速度 |
| `foot_pose[6]` | float | 足端姿态 |
| `duration` | int32 | 执行时长 |
| `contact` | int32 | 足端触地状态 |

**运动回报结构 `robot_control_response_lcmt`**（MR813→NX）：

| 字段 | 类型 | 含义 |
|------|------|------|
| `mode` | int32 | 当前运动模式 |
| `gait_id` | int32 | 当前步态 ID |
| `order_process_bar` | int32 | 指令执行进度 |
| `switch_status` | int32 | 模式切换状态 |
| `ori_error` | int32 | 姿态异常标志 |
| `footpos_error` | int32 | 足端位置异常 |
| `motor_error[12]` | int32 | 12 个电机错误码 |

相关代码见：
- 协议字定义：`motion/motion_action/include/motion_action/motion_macros.hpp`
- LCM 收发实现：`motion/motion_action/src/motion_action.cpp`
- LCM 桥接（IMU/里程计/电机温度）：`motion/motion_bridge/`

## 使用示例
可作为开发用参考demo，非原生功能

| demo名称                | 功能描述     | github地址                                             |
| ----------------------- | ------------ | ------------------------------------------------------ |
| grpc_demo               | grpc通信例程 | https://github.com/WLwind/grpc_demo                    |
| audio_demos             | 语音例程     | https://github.com/jiayy2/audio_demos                  |
| cyberdog_ai_sports_demo | 运动计数例程 | https://github.com/Ydw-588/cyberdog_ai_sports_demo     |
| cyberdog_face_demo      | 人脸识别demo | https://github.com/Ydw-588/cyberdog_face_demo          |
| nav2_demo               | 导航         | https://github.com/duyongquan/nav2_demo                |
| cyberdog_vp_demo        | 可视化编程   | https://github.com/szh-cn/cyberdog_vp_demo             |
| cyberdog_action_demo    | 手势动作识别 | https://github.com/liangxiaowei00/cyberdog_action_demo |


## MiRoboticsLab 开源仓库全景

小米机器人实验室在 GitHub 上共有 30 个仓库（[MiRoboticsLab](https://github.com/MiRoboticsLab)），以下按用途分类整理。

### 本仓库已包含（NX 主仓库 + 9 个子仓库）

| 仓库 | 本地目录 | 说明 |
|------|---------|------|
| [cyberdog_ws](https://github.com/MiRoboticsLab/cyberdog_ws) | `/`（本仓库根目录） | NX 主仓库，启动模块 |
| [bridges](https://github.com/MiRoboticsLab/bridges) | `bridges/` | ROS 消息/服务定义、APP 通信、CAN 封装 |
| [devices](https://github.com/MiRoboticsLab/devices) | `devices/` | 设备驱动（BMS/LED/UWB/Touch 等） |
| [interaction](https://github.com/MiRoboticsLab/interaction) | `interaction/` | 人机交互（语音/手势/GRPC/图传/快连） |
| [manager](https://github.com/MiRoboticsLab/manager) | `manager/` | 系统管理（含 unlock_request 解锁节点） |
| [motion](https://github.com/MiRoboticsLab/motion) | `motion/` | NX 侧运动指令管理与桥接 |
| [sensors](https://github.com/MiRoboticsLab/sensors) | `sensors/` | 传感器驱动（GPS/雷达/TOF/超声波） |
| [utils](https://github.com/MiRoboticsLab/utils) | `utils/` | 通用接口库 |
| [cyberdog_nav2](https://github.com/MiRoboticsLab/cyberdog_nav2) | `cyberdog_nav2/` | 导航与算法任务管理 |
| [cyberdog_tracking_base](https://github.com/MiRoboticsLab/cyberdog_tracking_base) | `cyberdog_tracking_base/` | 基于 Nav2 的跟踪/导航/Docking |

### MR813 运控板相关（需单独下载）

| 仓库 | 说明 | 推荐度 |
|------|------|--------|
| [cyberdog_locomotion](https://github.com/MiRoboticsLab/cyberdog_locomotion) | MR813 运动控制（MPC/WBC/RL），需 Docker 交叉编译 | ⭐⭐⭐⭐⭐ |
| [loco_hl_example](https://github.com/MiRoboticsLab/loco_hl_example) | 运控高层 Python 示例（基本步态/自定义步态/组合动作） | ⭐⭐⭐ |
| [cyberdog_motor_sdk](https://github.com/MiRoboticsLab/cyberdog_motor_sdk) | 电机 SDK，直接控制关节电机 | ⭐⭐⭐ |

### 仿真相关

| 仓库 | 说明 | 推荐度 |
|------|------|--------|
| [cyberdog_sim](https://github.com/MiRoboticsLab/cyberdog_sim) | Gazebo 仿真入口，拉取 locomotion + simulator | ⭐⭐⭐⭐⭐ |
| [cyberdog_simulator](https://github.com/MiRoboticsLab/cyberdog_simulator) | 仿真器代码，被 cyberdog_sim 引用 | ⭐⭐⭐⭐ |

### 视觉与导航（NX 上运行）

| 仓库 | 说明 | 推荐度 |
|------|------|--------|
| [cyberdog_vision](https://github.com/MiRoboticsLab/cyberdog_vision) | AI 视觉检测/识别 | ⭐⭐ |
| [cyberdog_miloc](https://github.com/MiRoboticsLab/cyberdog_miloc) | 视觉定位 | ⭐⭐ |
| [cyberdog_camera](https://github.com/MiRoboticsLab/cyberdog_camera) | 摄像头驱动 | ⭐⭐ |
| [cyberdog_laserslam](https://github.com/MiRoboticsLab/cyberdog_laserslam) | 激光 SLAM | ⭐⭐ |
| [cyberdog_mivins](https://github.com/MiRoboticsLab/cyberdog_mivins) | 视觉惯性导航 (VIO) | ⭐⭐ |
| [cyberdog_occmap](https://github.com/MiRoboticsLab/cyberdog_occmap) | 占据栅格地图 | ⭐⭐ |

### 文档与资料

| 仓库 | 说明 | 推荐度 |
|------|------|--------|
| [blogs](https://github.com/MiRoboticsLab/blogs) | 官方技术文档/教程（架构设计、Dockerfile 说明等） | ⭐⭐⭐⭐ |
| [Cyberdog_MD](https://github.com/MiRoboticsLab/Cyberdog_MD) | 硬件设计资料 | ⭐⭐ |
| [model_files](https://github.com/MiRoboticsLab/model_files) | 模型文件 | ⭐ |
| [MuKA](https://github.com/MiRoboticsLab/MuKA) | 未知，2025-02 新建 | ⭐ |

### 一般不需要

| 仓库 | 原因 |
|------|------|
| [cyberdog_ros2](https://github.com/MiRoboticsLab/cyberdog_ros2) | CyberDog **1 代**的 ROS2 包，与 2 代架构不同 |
| [realsense-ros](https://github.com/MiRoboticsLab/realsense-ros) | RealSense 官方 ROS 包的 fork，用官方的即可 |
| [cyberdog_tracking](https://github.com/MiRoboticsLab/cyberdog_tracking) | 已被 cyberdog_tracking_base 替代 |
| [cyberdog_visions_interfaces](https://github.com/MiRoboticsLab/cyberdog_visions_interfaces) | 视觉接口定义，体积小，单独用处不大 |
| [cyberdog_tegra_kernel](https://github.com/MiRoboticsLab/cyberdog_tegra_kernel) | NX 内核源码，除非需要改内核 |

## 文档

架构设计请参考： [平台架构](https://miroboticslab.github.io/blogs/#/cn/cyberdog_platform_software_architecture_cn)

详细文档请参考：[项目博客文档](https://miroboticslab.github.io/blogs/#/)

刷机请参考：[刷机包下载](https://s.xiaomi.cn/c/8JEpGDY8)

## 版权和许可

四足开发者平台遵循Apache License 2.0 开源协议。详细的协议内容请查看 [LICENSE.txt](./LICENSE.txt)

thirdparty：[第三方库](https://github.com/MiRoboticsLab/blogs/blob/rolling/docs/cn/third_party_library_management_cn.md)

## 联系方式

dukun1@xiaomi.com

liukai21@xiaomi.com

tianhonghai@xiaomi.com

wangruheng@xiaomi.com
