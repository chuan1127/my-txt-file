#!/bin/bash

# 确保脚本出错时立即退出
set -e
# 确保管道中的命令失败时也退出
set -o pipefail

# ==================================================
# 日志配置
# ==================================================
LOG_FILE="/app/webui/launch.log"
# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"
# 将所有标准输出和错误输出重定向到文件和控制台
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "🚀 [0] 启动脚本 - Stable Diffusion WebUI (CUDA 12.8 / PyTorch Nightly)"
echo "=================================================="
echo "⏳ 开始时间: $(date)"
echo "🔧 使用 PyTorch Nightly (Preview) builds 构建，可能存在不稳定风险。"
echo "🔧 xformers 已在 Docker 构建时从源码编译 (目标架构: 8.9 for RTX 4090)。"

# ==================================================
# 系统环境自检
# ==================================================
echo "🛠️  [0.5] 系统环境自检..."

# Python 检查 (应为 3.11)
if command -v python3.11 &>/dev/null; then
  echo "✅ Python 版本: $(python3.11 --version)"
else
  echo "❌ 未找到 python3.11，Dockerfile 配置可能存在问题！"
  exit 1
fi

# pip 检查 (通过 python -m pip 调用)
if python3.11 -m pip --version &>/dev/null; then
  echo "✅ pip for Python 3.11 版本: $(python3.11 -m pip --version)"
else
  echo "❌ 未找到 pip for Python 3.11！"
  exit 1
fi

# CUDA & GPU 检查 (nvidia-smi)
if command -v nvidia-smi &>/dev/null; then
  # 检查 nvidia-smi 输出中的 CUDA 版本
  # 注意：nvidia-smi 显示的 CUDA 版本是驱动支持的最高版本，可能高于运行时版本 (12.8)
  echo "✅ nvidia-smi 检测成功 (驱动应支持 CUDA >= 12.8)，GPU 信息如下："
  echo "---------------- Nvidia SMI Output Start -----------------"
  nvidia-smi
  echo "---------------- Nvidia SMI Output End -------------------"
else
  echo "⚠️ 未检测到 nvidia-smi 命令。可能原因：容器未加 --gpus all 启动，或 Nvidia 驱动未正确安装。"
  echo "⚠️ 无法验证 GPU 可用性，后续步骤可能失败。"
fi

# 容器检测
if [ -f "/.dockerenv" ]; then
  echo "📦 正在 Docker 容器中运行"
else
  echo "🖥️ 非 Docker 容器环境"
fi

# 用户检查 (应为 webui)
echo "👤 当前用户: $(whoami) (应为 webui)"

# 工作目录写入权限检查
if [ -w "/app/webui" ]; then
  echo "✅ /app/webui 目录可写"
else
  echo "❌ /app/webui 目录不可写，启动可能会失败！请检查 Dockerfile 中的权限设置。"
  # 允许继续，以便在具体步骤中捕获错误
fi
echo "✅ 系统环境自检完成"

# ==================================================
# 环境变量设置
# ==================================================
echo "🔧 [1] 解析 UI 与 ARGS 环境变量..."
# UI 类型，默认为 forge
UI="${UI:-forge}"
# 传递给 webui.sh 的参数，默认包含 --xformers
ARGS="${ARGS:---xformers --api --listen --enable-insecure-extension-access --theme dark}"
echo "  - UI 类型 (UI): ${UI}"
echo "  - WebUI 启动参数 (ARGS): ${ARGS}"

echo "🔧 [2] 解析下载开关环境变量 (默认全部启用)..."
# 解析全局下载开关
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"

# 解析独立的模型和资源类别开关
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_SD15="${ENABLE_DOWNLOAD_MODEL_SD15:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_SDXL="${ENABLE_DOWNLOAD_MODEL_SDXL:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_FLUX="${ENABLE_DOWNLOAD_MODEL_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE_FLUX="${ENABLE_DOWNLOAD_VAE_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TE_FLUX="${ENABLE_DOWNLOAD_TE_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_SD15="${ENABLE_DOWNLOAD_CNET_SD15:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_SDXL="${ENABLE_DOWNLOAD_CNET_SDXL:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_FLUX="${ENABLE_DOWNLOAD_CNET_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_LORAS="${ENABLE_DOWNLOAD_LORAS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_EMBEDDINGS="${ENABLE_DOWNLOAD_EMBEDDINGS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_UPSCALERS="${ENABLE_DOWNLOAD_UPSCALERS:-$ENABLE_DOWNLOAD_ALL}"

# 解析独立的镜像使用开关
USE_HF_MIRROR="${USE_HF_MIRROR:-false}" # 控制是否使用 hf-mirror.com
USE_GIT_MIRROR="${USE_GIT_MIRROR:-false}" # 控制是否使用 gitcode.net

echo "  - 下载总开关        (ENABLE_DOWNLOAD_ALL): ${ENABLE_DOWNLOAD_ALL}"
echo "  - 下载 Extensions   (ENABLE_DOWNLOAD_EXTS): ${ENABLE_DOWNLOAD_EXTS}"
echo "  - 下载 Checkpoint SD1.5 (ENABLE_DOWNLOAD_MODEL_SD15): ${ENABLE_DOWNLOAD_MODEL_SD15}"
echo "  - 下载 Checkpoint SDXL  (ENABLE_DOWNLOAD_MODEL_SDXL): ${ENABLE_DOWNLOAD_MODEL_SDXL}"
echo "  - 下载 Checkpoint FLUX (ENABLE_DOWNLOAD_MODEL_FLUX): ${ENABLE_DOWNLOAD_MODEL_FLUX}"
echo "  - 下载 VAE FLUX       (ENABLE_DOWNLOAD_VAE_FLUX): ${ENABLE_DOWNLOAD_VAE_FLUX}"
echo "  - 下载 TE FLUX        (ENABLE_DOWNLOAD_TE_FLUX): ${ENABLE_DOWNLOAD_TE_FLUX}"
echo "  - 下载 ControlNet SD1.5 (ENABLE_DOWNLOAD_CNET_SD15): ${ENABLE_DOWNLOAD_CNET_SD15}"
echo "  - 下载 ControlNet SDXL  (ENABLE_DOWNLOAD_CNET_SDXL): ${ENABLE_DOWNLOAD_CNET_SDXL}"
echo "  - 下载 ControlNet FLUX  (ENABLE_DOWNLOAD_CNET_FLUX): ${ENABLE_DOWNLOAD_CNET_FLUX}"
echo "  - 下载 通用 VAE     (ENABLE_DOWNLOAD_VAE): ${ENABLE_DOWNLOAD_VAE}"
echo "  - 下载 LoRAs/LyCORIS (ENABLE_DOWNLOAD_LORAS): ${ENABLE_DOWNLOAD_LORAS}"
echo "  - 下载 Embeddings   (ENABLE_DOWNLOAD_EMBEDDINGS): ${ENABLE_DOWNLOAD_EMBEDDINGS}"
echo "  - 下载 Upscalers    (ENABLE_DOWNLOAD_UPSCALERS): ${ENABLE_DOWNLOAD_UPSCALERS}"
echo "  - 是否使用 HF 镜像  (USE_HF_MIRROR): ${USE_HF_MIRROR}" # (hf-mirror.com)
echo "  - 是否使用 Git 镜像 (USE_GIT_MIRROR): ${USE_GIT_MIRROR}" # (gitcode.net)

# 预定义镜像地址 (如果需要可以从环境变量读取，但简单起见先硬编码)
HF_MIRROR_URL="https://hf-mirror.com"
GIT_MIRROR_URL="https://gitcode.net" # 使用 https

# TCMalloc 和 Pip 索引设置
export NO_TCMALLOC=1
export PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/nightly/cu128"
echo "  - 禁用的 TCMalloc (NO_TCMALLOC): ${NO_TCMALLOC}"
echo "  - pip 额外索引 (PIP_EXTRA_INDEX_URL): ${PIP_EXTRA_INDEX_URL} (用于 PyTorch Nightly cu128)"

# ==================================================
# 设置 Git 源路径
# ==================================================
echo "🔧 [3] 设置 WebUI 仓库路径与 Git 源 (通常为最新开发版/Preview)..."
TARGET_DIR="" # 初始化
REPO=""       # 初始化
WEBUI_EXECUTABLE="webui.sh" # 默认启动脚本名称

# 根据 UI 环境变量设置目标目录和仓库 URL
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/webui/stable-diffusion-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/webui/sd-webui-forge"
  # 使用官方 Forge 仓库
  REPO="https://github.com/lllyasviel/stable-diffusion-webui-forge.git"
  # 如果需要特定 fork，在此处修改:
  # REPO="https://github.com/amDosion/stable-diffusion-webui-forge-cuda128.git"
elif [ "$UI" = "stable_diffusion_webui" ]; then # auto 的别名
  TARGET_DIR="/app/webui/stable-diffusion-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
else
  echo "❌ 未知的 UI 类型: $UI。请设置 UI 环境变量为 'auto', 'forge' 或 'stable_diffusion_webui'。"
  exit 1
fi
echo "  - 目标目录: $TARGET_DIR"
echo "  - Git 仓库源: $REPO (将克隆默认/主分支)"

# ==================================================
# 克隆/更新 WebUI 仓库
# ==================================================
echo "🔄 [4] 克隆或更新 WebUI 仓库..."
# 检查仓库是否已存在
if [ -d "$TARGET_DIR/.git" ]; then
  echo "  - 仓库已存在于 $TARGET_DIR，尝试更新 (git pull)..."
  # 进入目录执行 git pull, --ff-only 避免合并冲突
  cd "$TARGET_DIR"
  git pull --ff-only || echo "⚠️ Git pull 失败，可能是本地有修改或网络问题。将继续使用当前版本。"
  # 操作完成后返回上层目录
  cd /app/webui
else
  echo "  - 仓库不存在，开始克隆 $REPO 到 $TARGET_DIR (浅克隆)..."
  # 使用 --depth 1 浅克隆，节省时间和空间
  git clone --depth=1 "$REPO" "$TARGET_DIR"
  # 赋予启动脚本执行权限
  if [ -f "$TARGET_DIR/$WEBUI_EXECUTABLE" ]; then
      chmod +x "$TARGET_DIR/$WEBUI_EXECUTABLE"
      echo "  - 已赋予 $TARGET_DIR/$WEBUI_EXECUTABLE 执行权限"
  else
      echo "⚠️ 未在克隆的仓库 $TARGET_DIR 中找到预期的启动脚本 $WEBUI_EXECUTABLE"
      # 考虑是否需要添加错误处理或退出逻辑
  fi
fi
echo "✅ 仓库操作完成"

# 切换到 WebUI 目标目录进行后续操作
cd "$TARGET_DIR" || { echo "❌ 无法切换到 WebUI 目标目录 $TARGET_DIR"; exit 1; }

# ==================================================
# requirements 文件检查 (仅非 Forge UI)
# ==================================================
# Forge UI 有自己的依赖管理方式，通常通过其启动脚本处理
if [ "$UI" != "forge" ]; then
    echo "🔧 [5] (非 Forge UI) 检查 requirements 文件..."
    REQ_FILE_CHECK="requirements_versions.txt"
    if [ ! -f "$REQ_FILE_CHECK" ]; then
        REQ_FILE_CHECK="requirements.txt" # 回退检查 requirements.txt
    fi
    if [ -f "$REQ_FILE_CHECK" ]; then
        echo "  - 将使用 $REQ_FILE_CHECK 文件安装依赖。"
        # 此处不进行清理，依赖文件应保持原样
    else
        echo "  - ⚠️ 未找到 $REQ_FILE_CHECK 或 requirements.txt。依赖安装可能不完整。"
    fi
else
    # 对于 Forge，跳过此步骤
    echo "⚙️ [5] (Forge UI) 跳过手动处理 requirements 文件的步骤 (由 Forge $WEBUI_EXECUTABLE 自行处理)。"
fi

# ==================================================
# 权限设置 (警告)
# ==================================================
# 警告：赋予 777 权限可能带来安全风险。
# 仅在明确需要且了解后果时使用。更好的做法是精细控制权限。
echo "⚠️ [5.5] 正在为当前目录 ($TARGET_DIR) 设置递归 777 权限。这在生产环境中不推荐！"
chmod -R 777 . || echo "⚠️ chmod 777 失败，后续步骤可能因权限问题失败。"

# ==================================================
# Python 虚拟环境设置与依赖安装
# ==================================================
VENV_DIR="venv" # 定义虚拟环境目录名
echo "🐍 [6] 设置 Python 虚拟环境 ($VENV_DIR)..."

# 检查虚拟环境是否已正确创建
if [ ! -x "$VENV_DIR/bin/activate" ]; then
  echo "  - 虚拟环境不存在或未正确创建，现在使用 python3.11 创建..."
  # 移除可能存在的无效目录
  rm -rf "$VENV_DIR"
  # 使用明确的 Python 版本创建
  python3.11 -m venv "$VENV_DIR"
  echo "  - 虚拟环境创建成功。"
else
  echo "  - 虚拟环境已存在于 $VENV_DIR。"
fi

echo "  - 激活虚拟环境..."
# 激活虚拟环境
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

# 确认 venv 内的 Python 和 pip
echo "  - 当前 Python: $(which python) (应指向 $VENV_DIR/bin/python)"
echo "  - 当前 pip: $(which pip) (应指向 $VENV_DIR/bin/pip)"

echo "📥 [6.1] 升级 venv 内的 pip 到最新版本..."
pip install --upgrade pip | tee -a "$LOG_FILE" # 同时输出到控制台和日志

echo "🔧 [6.1.1] 安装 huggingface_hub CLI 工具..."
# 确保命令行登录功能可用
pip install --upgrade "huggingface_hub[cli]" | tee -a "$LOG_FILE"

# ==================================================
# 安装 WebUI 核心依赖 (基于 UI 类型)
# ==================================================
echo "📥 [6.2] 安装 WebUI 核心依赖 (基于 UI 类型)..."

# 如果是 Forge UI，跳过手动安装，依赖其启动脚本
if [ "$UI" = "forge" ]; then
    echo "  - (Forge UI) 依赖安装将由 $WEBUI_EXECUTABLE 处理，此处跳过手动 pip install。"
    echo "  - Forge 通常会处理 xformers 等关键依赖的安装或检查。"
else
    # 如果是 Automatic1111 或其他非 Forge UI
    REQ_FILE_TO_INSTALL="requirements_versions.txt" # 优先使用版本锁定的文件
    if [ ! -f "$REQ_FILE_TO_INSTALL" ]; then
        REQ_FILE_TO_INSTALL="requirements.txt" # 否则使用普通 requirements 文件
    fi

    # 如果找到了依赖文件
    if [ -f "$REQ_FILE_TO_INSTALL" ]; then
        echo "  - 使用 $REQ_FILE_TO_INSTALL 安装依赖 (允许预发布版本 --pre)..."
        # 添加注释，说明 xformers 已在 Dockerfile 中构建
        echo "  - (注意: xformers 预计已在 Dockerfile 中从源码构建，pip 应跳过)"
        # 修复可能的 Windows 换行符 (保险起见)
        sed -i 's/\r$//' "$REQ_FILE_TO_INSTALL"
        # 逐行读取依赖文件并安装
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 清理行内容：移除注释、前后空格
            line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            # 跳过空行
            [[ -z "$line" ]] && continue

            echo "    - 安装: ${line}"
            # 使用 --pre 允许安装预发布版本 (对 Nightly 环境兼容性重要)
            # 使用 --no-cache-dir 减少镜像体积/缓存问题
            # 使用 --extra-index-url 查找 PyTorch Nightly 包
            pip install --pre "${line}" --no-cache-dir --extra-index-url "$PIP_EXTRA_INDEX_URL" 2>&1 \
                | tee -a "$LOG_FILE" \
                | sed 's/^Successfully installed/      ✅ 成功安装/' \
                | sed 's/^Requirement already satisfied/      ⏩ 需求已满足/' # 更好地显示跳过的包
            # 检查 pip install 的退出状态
            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                echo "❌ 安装失败: ${line}"
                # 可以考虑在此处添加退出逻辑 `exit 1`，如果单个依赖失败就中断
            fi
        done < "$REQ_FILE_TO_INSTALL"
        echo "  - $REQ_FILE_TO_INSTALL 中的依赖处理完成。"
    else
        # 如果找不到依赖文件
        echo "⚠️ 未找到 $REQ_FILE_TO_INSTALL 或 requirements.txt，无法自动安装核心依赖。请检查 WebUI 仓库内容。"
    fi
fi # 结束 UI 类型判断

# ==================================================
# TensorFlow 安装 (可选，在 venv 内)
# ==================================================
# 通过环境变量 INSTALL_TENSORFLOW 控制是否安装，默认为 false
INSTALL_TENSORFLOW="${INSTALL_TENSORFLOW:-false}"
if [[ "$INSTALL_TENSORFLOW" == "true" ]]; then
    echo "🧠 [6.4] 按需安装 TensorFlow (版本需兼容 CUDA 12.8)..."
    # 检查 CPU 是否支持 AVX2 (TensorFlow 官方包需要)
    echo "  - 正在检测 CPU 支持情况..."
    CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "未知")
    AVX2_SUPPORTED=$(grep -q avx2 /proc/cpuinfo && echo "true" || echo "false")
    echo "    - CPU Vendor: ${CPU_VENDOR}"
    echo "    - AVX2 支持: ${AVX2_SUPPORTED}"

    # 设置 TensorFlow 版本 (选择一个已知支持 CUDA 12.x 的版本)
    TF_VERSION="2.16.1"
    TF_CPU_VERSION="2.16.1"
    echo "    - 目标 TensorFlow 版本: ${TF_VERSION} (GPU) / ${TF_CPU_VERSION} (CPU)"

    # 仅在支持 AVX2 时尝试安装官方包
    if [[ "$AVX2_SUPPORTED" == "true" ]]; then
        echo "    - AVX2 支持，继续安装 TensorFlow..."
        # 尝试卸载可能存在的旧版本
        echo "    - 尝试卸载旧的 TensorFlow (以防万一)..."
        pip uninstall -y tensorflow tensorflow-cpu tensorflow-gpu tensorboard tf-nightly &>/dev/null || true
        TF_PACKAGE="" # 初始化包名

        # 检测是否有 GPU (通过 nvidia-smi) 来决定安装 GPU 还是 CPU 版本
        if command -v nvidia-smi &>/dev/null; then
            echo "    - 检测到 GPU (nvidia-smi)，尝试安装 TensorFlow GPU 版本: ${TF_VERSION}..."
            TF_PACKAGE="tensorflow==${TF_VERSION}"
        else
            echo "    - 未检测到 GPU，安装 TensorFlow CPU 版本: ${TF_CPU_VERSION}..."
            TF_PACKAGE="tensorflow-cpu==${TF_CPU_VERSION}"
        fi

        # 执行安装
        echo "    - 安装: ${TF_PACKAGE}"
        pip install "${TF_PACKAGE}" --no-cache-dir | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "❌ TensorFlow 安装失败!"
            # 可以考虑添加退出逻辑
        else
            echo "    - ✅ TensorFlow (${TF_PACKAGE}) 安装命令执行完成。"
            # 如果安装了 GPU 版本，进行验证
            echo "    - 🧪 验证 TensorFlow 可用性..."
            if [[ "$TF_PACKAGE" == *"tensorflow=="* ]]; then
                # 使用 python -c 执行验证脚本
                python -c "import warnings; warnings.filterwarnings('ignore', category=FutureWarning); warnings.filterwarnings('ignore', category=UserWarning); import tensorflow as tf; print(f'TensorFlow Version: {tf.__version__}'); gpus = tf.config.list_physical_devices('GPU'); print(f'Num GPUs Available: {len(gpus)}'); print(f'Available GPUs: {gpus}'); assert len(gpus) > 0, 'TensorFlow failed to detect GPU'"
                if [ $? -eq 0 ]; then
                    echo "    - ✅ TensorFlow 成功检测到 GPU！"
                else
                    echo "    - ⚠️ TensorFlow 未能检测到 GPU 或验证失败。请检查 CUDA/cuDNN 版本与 TensorFlow 版本的兼容性以及 Nvidia 驱动。"
                fi
            else
                 echo "    - (安装了 CPU 版本，进行 CPU 验证)"
                 python -c "import tensorflow as tf; print(f'TensorFlow Version: {tf.__version__}'); print('TensorFlow CPU version confirmed.')"
            fi
        fi
    else
        # 如果不支持 AVX2
        echo "    - ⚠️ 未检测到 AVX2 指令集。标准的 TensorFlow pip 包可能无法运行。"
        echo "    - 跳过 TensorFlow 安装。如果需要，请考虑从源码编译或使用其他提供非 AVX2 支持的 TensorFlow 构建。"
        # 可以选择安装一个旧版本或特定构建，但这超出了标准安装范围
    fi
else
    # 如果 INSTALL_TENSORFLOW 不为 true
    echo "⏭️ [6.4] 跳过 TensorFlow 安装 (INSTALL_TENSORFLOW 未设置为 true)。"
fi # 结束 TensorFlow 安装块

# ==================================================
# 创建 WebUI 相关目录
# ==================================================
echo "📁 [7] 确保 WebUI 主要工作目录存在..."
# 创建常用的子目录，如果不存在的话
mkdir -p embeddings models/Stable-diffusion models/VAE models/Lora models/LyCORIS models/ControlNet outputs extensions || echo "⚠️ 创建部分目录失败，请检查权限。"
echo "  - 主要目录检查/创建完成。"

# ==================================================
# 网络测试 (可选)
# ==================================================
echo "🌐 [8] 网络连通性测试 (尝试访问 huggingface.co)..."
NET_OK=false # 默认网络不通
# 使用 curl 测试连接，设置超时时间
if curl -fsS --connect-timeout 5 https://huggingface.co > /dev/null; then
  NET_OK=true
  echo "  - ✅ 网络连通 (huggingface.co 可访问)"
else
  # 如果 Hugging Face 不通，尝试 GitHub 作为备选检查
  if curl -fsS --connect-timeout 5 https://github.com > /dev/null; then
      NET_OK=true # 至少 Git 相关操作可能成功
      echo "  - ⚠️ huggingface.co 无法访问，但 github.com 可访问。部分模型下载可能受影响。"
  else
      echo "  - ❌ 网络不通 (无法访问 huggingface.co 和 github.com)。资源下载和插件更新将失败！"
  fi
fi

# ==================================================
# 资源下载 (使用 resources.txt)
# ==================================================
echo "📦 [9] 处理资源下载 (基于 /app/webui/resources.txt 和下载开关)..."
RESOURCE_PATH="/app/webui/resources.txt" # 定义资源列表文件路径

# 检查资源文件是否存在，如果不存在则尝试下载默认版本
if [ ! -f "$RESOURCE_PATH" ]; then
  # 指定默认资源文件的 URL
  DEFAULT_RESOURCE_URL="https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt"
  echo "  - 未找到本地 resources.txt，尝试从 ${DEFAULT_RESOURCE_URL} 下载..."
  # 使用 curl 下载，确保失败时不输出错误页面 (-f)，静默 (-s)，跟随重定向 (-L)
  curl -fsSL -o "$RESOURCE_PATH" "$DEFAULT_RESOURCE_URL"
  if [ $? -eq 0 ]; then
      echo "  - ✅ 默认 resources.txt 下载成功。"
  else
      echo "  - ❌ 下载默认 resources.txt 失败。请手动将资源文件放在 ${RESOURCE_PATH} 或检查网络/URL。"
      # 创建一个空文件以避免后续读取错误，但不会下载任何内容
      touch "$RESOURCE_PATH"
      echo "  - 已创建空的 resources.txt 文件以继续，但不会下载任何资源。"
  fi
else
  echo "  - ✅ 使用本地已存在的 resources.txt: ${RESOURCE_PATH}"
fi

# 定义函数：克隆或更新 Git 仓库 (支持独立 Git 镜像开关)
clone_or_update_repo() {
    # $1: 目标目录, $2: 原始仓库 URL
    local dir="$1" repo_original="$2"
    local dirname
    local repo_url # URL to be used for cloning/pulling

    dirname=$(basename "$dir")

    # 检查是否启用了 Git 镜像以及是否是 GitHub URL
    # 使用步骤 [2] 中定义的 GIT_MIRROR_URL
    if [[ "$USE_GIT_MIRROR" == "true" && "$repo_original" == "https://github.com/"* ]]; then
        # 替换 github.com 为镜像地址 (只替换域名部分)
        # 从 GIT_MIRROR_URL 提取 host
        local git_mirror_host
        git_mirror_host=$(echo "$GIT_MIRROR_URL" | sed 's|https://||; s|http://||; s|/.*||')
        repo_url=$(echo "$repo_original" | sed "s|github.com|$git_mirror_host|")
        echo "    - 使用镜像转换 (Git): $repo_original -> $repo_url"
    else
        # 使用原始 URL
        repo_url="$repo_original"
    fi

    # 检查扩展下载开关
    if [[ "$ENABLE_DOWNLOAD_EXTS" != "true" ]]; then
         if [ -d "$dir" ]; then
            echo "    - ⏭️ 跳过更新扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
         else
            echo "    - ⏭️ 跳过克隆扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
         fi
         return
    fi

    # 尝试更新或克隆
    if [ -d "$dir/.git" ]; then
        echo "    - 🔄 更新扩展/仓库: $dirname (from $repo_url)"
        (cd "$dir" && git pull --ff-only) || echo "      ⚠️ Git pull 失败: $dirname (可能存在本地修改或网络问题)"
    elif [ ! -d "$dir" ]; then
        echo "    - 📥 克隆扩展/仓库: $repo_url -> $dirname (浅克隆)"
        git clone --depth=1 "$repo_url" "$dir" || echo "      ❌ Git clone 失败: $dirname (检查 URL: $repo_url 和网络)"
    else
        echo "    - ✅ 目录已存在但非 Git 仓库，跳过 Git 操作: $dirname"
    fi
}

# 定义函数：下载文件 (支持独立 HF 镜像开关)
download_with_progress() {
    # $1: 输出路径, $2: 原始 URL, $3: 资源类型描述, $4: 对应的下载开关变量值
    local output_path="$1" url_original="$2" type="$3" enabled_flag="$4"
    local filename
    local download_url # URL to be used for downloading

    filename=$(basename "$output_path")

    # 检查下载开关
    if [[ "$enabled_flag" != "true" ]]; then
        echo "    - ⏭️ 跳过下载 ${type} (开关 '$enabled_flag' != 'true'): $filename"
        return
    fi
    # 检查网络
    if [[ "$NET_OK" != "true" ]]; then
        echo "    - ❌ 跳过下载 ${type} (网络不通): $filename"
        return
    fi

    # 检查是否启用了 HF 镜像以及是否是 Hugging Face URL
    # 使用步骤 [2] 中定义的 HF_MIRROR_URL
    if [[ "$USE_HF_MIRROR" == "true" && "$url_original" == "https://huggingface.co/"* ]]; then
        # 替换 huggingface.co 为镜像地址
        download_url=$(echo "$url_original" | sed "s|https://huggingface.co|$HF_MIRROR_URL|")
        echo "    - 使用镜像转换 (HF): $url_original -> $download_url"
    else
        # 使用原始 URL
        download_url="$url_original"
    fi

    # 检查文件是否已存在
    if [ ! -f "$output_path" ]; then
        echo "    - ⬇️ 下载 ${type}: $filename (from $download_url)"
        mkdir -p "$(dirname "$output_path")"
        # 执行下载
        wget --progress=bar:force:noscroll --timeout=120 -O "$output_path" "$download_url"
        # 检查结果
        if [ $? -ne 0 ]; then
            echo "      ❌ 下载失败: $filename from $download_url (检查 URL 或网络)"
            rm -f "$output_path"
        else
            echo "      ✅ 下载完成: $filename"
        fi
    else
        echo "    - ✅ 文件已存在，跳过下载 ${type}: $filename"
    fi
}

# 定义插件/目录黑名单 (示例)
SKIP_DIRS=(
  "extensions/stable-diffusion-aws-extension" # 示例：跳过 AWS 插件
  "extensions/sd_dreambooth_extension"     # 示例：跳过 Dreambooth (如果需要单独管理)
)
# 函数：检查目标路径是否应跳过
should_skip() {
  local dir_to_check="$1"
  for skip_dir in "${SKIP_DIRS[@]}"; do
    # 完全匹配路径
    if [[ "$dir_to_check" == "$skip_dir" ]]; then
      return 0 # 0 表示应该跳过 (Bash true)
    fi
  done
  return 1 # 1 表示不应该跳过 (Bash false)
}

echo "  - 开始处理 resources.txt 中的条目..."
# 逐行读取 resources.txt 文件 (逗号分隔: 目标路径,源URL)
while IFS=, read -r target_path source_url || [[ -n "$target_path" ]]; do
  # 清理路径和 URL 的前后空格
  target_path=$(echo "$target_path" | xargs)
  source_url=$(echo "$source_url" | xargs)

  # 跳过注释行 (# 开头) 或空行 (路径或 URL 为空)
  [[ "$target_path" =~ ^#.*$ || -z "$target_path" || -z "$source_url" ]] && continue

  # 检查是否在黑名单中
  if should_skip "$target_path"; then
    echo "    - ⛔ 跳过黑名单条目: $target_path"
    continue # 处理下一行
  fi


# 根据目标路径判断资源类型并调用相应下载函数及正确的独立开关
case "$target_path" in
    # 1. Extensions
    extensions/*)
        clone_or_update_repo "$target_path" "$source_url" # Uses ENABLE_DOWNLOAD_EXTS internally
        ;;

    # 2. Stable Diffusion Checkpoints
    models/Stable-diffusion/SD1.5/*)
        download_with_progress "$target_path" "$source_url" "SD 1.5 Checkpoint" "$ENABLE_DOWNLOAD_MODEL_SD15"
        ;;
    models/Stable-diffusion/XL/*)
        download_with_progress "$target_path" "$source_url" "SDXL Checkpoint" "$ENABLE_DOWNLOAD_MODEL_SDXL"
        ;;
    models/Stable-diffusion/flux/*)
        download_with_progress "$target_path" "$source_url" "FLUX Checkpoint" "$ENABLE_DOWNLOAD_MODEL_FLUX"
        ;;
    models/Stable-diffusion/*) # Fallback
        echo "    - ❓ 处理未分类 Stable Diffusion 模型: $target_path (默认使用 SD1.5 开关)"
        download_with_progress "$target_path" "$source_url" "SD 1.5 Checkpoint (Fallback)" "$ENABLE_DOWNLOAD_MODEL_SD15"
        ;;

    # 3. VAEs
    models/VAE/flux-*.safetensors) # FLUX Specific VAE
        download_with_progress "$target_path" "$source_url" "FLUX VAE" "$ENABLE_DOWNLOAD_VAE_FLUX" # Use specific FLUX VAE switch
        ;;
    models/VAE/*) # Other VAEs
        download_with_progress "$target_path" "$source_url" "VAE Model" "$ENABLE_DOWNLOAD_VAE"
        ;;

    # 4. Text Encoders (Currently FLUX specific)
    models/text_encoder/*)
        download_with_progress "$target_path" "$source_url" "Text Encoder (FLUX)" "$ENABLE_DOWNLOAD_TE_FLUX" # Use specific FLUX TE switch
        ;;

    # 5. ControlNet Models
    models/ControlNet/*)
        if [[ "$target_path" == *sdxl* || "$target_path" == *SDXL* ]]; then
            download_with_progress "$target_path" "$source_url" "ControlNet SDXL" "$ENABLE_DOWNLOAD_CNET_SDXL"
        elif [[ "$target_path" == *flux* || "$target_path" == *FLUX* ]]; then
            download_with_progress "$target_path" "$source_url" "ControlNet FLUX" "$ENABLE_DOWNLOAD_CNET_FLUX"
        # Use keywords sd15 or v11 as indicators for SD 1.5 ControlNets
        elif [[ "$target_path" == *sd15* || "$target_path" == *SD15* || "$target_path" == *v11p* || "$target_path" == *v11e* || "$target_path" == *v11f* ]]; then
             download_with_progress "$target_path" "$source_url" "ControlNet SD 1.5" "$ENABLE_DOWNLOAD_CNET_SD15"
        else
            echo "    - ❓ 处理未分类 ControlNet 模型: $target_path (默认使用 SD1.5 ControlNet 开关)"
            download_with_progress "$target_path" "$source_url" "ControlNet SD 1.5 (Fallback)" "$ENABLE_DOWNLOAD_CNET_SD15"
        fi
        ;;

    # 6. LoRA and related models
    models/Lora/* | models/LyCORIS/* | models/LoCon/*)
        download_with_progress "$target_path" "$source_url" "LoRA/LyCORIS" "$ENABLE_DOWNLOAD_LORAS"
        ;;

    # 7. Embeddings / Textual Inversion
    models/TextualInversion/* | embeddings/*)
       download_with_progress "$target_path" "$source_url" "Embedding/Textual Inversion" "$ENABLE_DOWNLOAD_EMBEDDINGS"
       ;;

    # 8. Upscalers
    models/Upscaler/* | models/ESRGAN/*)
       download_with_progress "$target_path" "$source_url" "Upscaler Model" "$ENABLE_DOWNLOAD_UPSCALERS"
       ;;

    # 9. Fallback for any other paths
    *)
        if [[ "$source_url" == *.git ]]; then
             echo "    - ❓ 处理未分类 Git 仓库: $target_path (默认使用 Extension 开关)"
             clone_or_update_repo "$target_path" "$source_url" # Uses ENABLE_DOWNLOAD_EXTS internally
        elif [[ "$source_url" == http* ]]; then
             echo "    - ❓ 处理未分类文件下载: $target_path (默认使用 SD1.5 Model 开关)"
             download_with_progress "$target_path" "$source_url" "Unknown Model/File" "$ENABLE_DOWNLOAD_MODEL_SD15"
        else
             echo "    - ❓ 无法识别的资源类型或无效 URL: target='$target_path', source='$source_url'"
        fi
        ;;
esac # End case
done < "$RESOURCE_PATH" # 从资源文件读取
echo "✅ 资源下载处理完成。"

# ==================================================
# Token 处理 (Hugging Face, Civitai)
# ==================================================
# 步骤号顺延为 [10]
echo "🔐 [10] 处理 API Tokens (如果已提供)..."

# 处理 Hugging Face Token (如果环境变量已设置)
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "  - 检测到 HUGGINGFACE_TOKEN，尝试使用 huggingface-cli 登录..."
  # 检查 huggingface-cli 命令是否存在 (应由 huggingface_hub[cli] 提供)
  if command -v huggingface-cli &>/dev/null; then
      # 正确用法：将 token 作为参数传递给 --token
      huggingface-cli login --token "$HUGGINGFACE_TOKEN" --add-to-git-credential
      # 检查命令执行是否成功
      if [ $? -eq 0 ]; then
          echo "  - ✅ Hugging Face CLI 登录成功。"
      else
          # 登录失败通常不会是致命错误，只记录警告
          echo "  - ⚠️ Hugging Face CLI 登录失败。请检查 Token 是否有效、是否过期或 huggingface-cli 是否工作正常。"
      fi
  else
      echo "  - ⚠️ 未找到 huggingface-cli 命令，无法登录。请确保依赖 'huggingface_hub[cli]' 已正确安装在 venv 中。"
  fi
else
  # 如果未提供 Token
  echo "  - ⏭️ 未设置 HUGGINGFACE_TOKEN 环境变量，跳过 Hugging Face 登录。"
fi

# 检查 Civitai API Token
if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "  - ✅ 检测到 CIVITAI_API_TOKEN (长度: ${#CIVITAI_API_TOKEN})。"
else
  echo "  - ⏭️ 未设置 CIVITAI_API_TOKEN 环境变量。"
fi

# ==================================================
# 🔥 启动 WebUI (使用 venv 内的 Python)
# ==================================================
echo "🚀 [11] 所有准备工作完成，开始启动 WebUI (直接执行 launch.py)..."
echo "  - UI Type: ${UI}"
# Forge 的 launch.py 通常接受类似的参数
# 移除传递给 bash 的 -f 参数，直接将 $ARGS 传递给 launch.py
echo "  - Arguments: ${ARGS}" # 注意：不再自动加 -f

# 确认仍在 WebUI 的目标目录下
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" != "$TARGET_DIR" ]]; then
     echo "⚠️ 当前目录 ($CURRENT_DIR) 不是预期的 WebUI 目录 ($TARGET_DIR)，尝试切换..."
     cd "$TARGET_DIR" || { echo "❌ 无法切换到目录 $TARGET_DIR，启动失败！"; exit 1; }
     echo "✅ 已切换到目录: $(pwd)"
fi

# 确认 launch.py 文件存在
if [ ! -f "launch.py" ]; then
    echo "❌ 错误: 未在当前目录 ($(pwd)) 中找到 launch.py 文件！"
    exit 1
fi

# 记录最终启动时间
echo "⏳ WebUI 启动时间: $(date)"
# 使用 venv 内的 python 解释器直接执行 launch.py
echo "🚀 Executing: $VENV_DIR/bin/python launch.py $ARGS"

# 使用 exec 将当前 shell 进程替换为 launch.py 进程
exec "$VENV_DIR/bin/python" launch.py $ARGS

# 如果 exec 成功执行，脚本不会到达这里
# 如果 exec 失败
echo "❌ 启动 launch.py 失败！请检查脚本是否存在、是否有执行权限以及之前的日志输出。"
exit 1
