# Mole 小白使用指南

## 第一步：打开终端

终端是 Mac 自带的一个工具，用来输入命令操作电脑。

**方法一：快捷键（推荐）**

1. 按 `Command (⌘)` + `空格键`
2. 在搜索框输入 `终端` 或 `Terminal`
3. 按回车

**方法二：应用程序**

1. 打开访达
2. 点左侧的应用程序
3. 找到实用工具文件夹
4. 双击终端

---

## 第二步：安装 Mole

**方法一：一键安装（推荐）**

复制下面命令，粘贴到终端，按回车：

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash
```

**方法二：Homebrew**

```bash
brew install tw93/tap/mole
```


---

## 第三步：开始使用

终端输入 `mo` 回车。找不到命令就试 `mole`。

**操作方式：**

- `↑` `↓` 选菜单
- `空格` 选中/取消
- `回车` 确认
- `q` 退出

---

## 第四步：常见操作

### 重要提示

**首次使用建议：**

1. 先跑 `mo clean --dry-run` 看看会删什么，不会真删
2. 用 `mo clean --whitelist` 保护重要缓存
3. Mac 很重要的话，等 Mole 更成熟再用

### 清理垃圾文件

**预览模式：**

```bash
mo clean --dry-run
```

只显示会删什么，不会真删。

**白名单管理：**

```bash
mo clean --whitelist
```

选哪些缓存不删。

**正式清理：**

```bash
mo clean
```

清理系统缓存、日志、临时文件等。Mole 只删可重新生成的文件。

### 卸载应用

```bash
mo uninstall
```

方向键选，空格标记，回车确认。连残留文件一起删。

### 磁盘空间分析

```bash
mo analyze
```

看哪些文件和文件夹占空间大。

**操作：** `↑` `↓` 选择、`回车` 进入、`←` 返回、`Delete` 删除、`q` 退出

### 查看帮助

```bash
mo --help
```

---

## 第五步：注意事项

**推荐：** 每月清理一次，或磁盘快满时

**避免：** 频繁清理，或运行重要程序时清理

**安全：** Mole 只删缓存和日志，不碰应用配置、应用数据、系统文件、数据库

---

## 常见问题

**输密码看不到字符？** 终端安全设计，直接输完按回车。

**安装失败？** 检查网络，重新跑命令，还不行去 [GitHub Issues](https://github.com/tw93/mole/issues) 问。

**清理后能恢复吗？** 不用恢复。Mole 只删缓存和日志，应用会自动重新生成。应用卸载后无法恢复。

**多久清理一次？** 每月一次，或磁盘快满时。

**怎么更新？** `mo update`

**怎么卸载？** `mo remove`

**支持 Touch ID 吗？** Mole 用 `sudo` 请求权限，如果你给 `sudo` 启用了 Touch ID 就能用。

**如何启用 Touch ID？**

1. 终端输入 `sudo nano /etc/pam.d/sudo`
2. 在顶部注释下加 `auth sufficient pam_tid.so`
3. `Ctrl+O` 回车，`Ctrl+X` 退出

---

## 需要帮助？

- [GitHub 主页](https://github.com/tw93/mole)
- [提交问题](https://github.com/tw93/mole/issues)
- [完整文档](./README.md)

有用的话分享给朋友吧~
