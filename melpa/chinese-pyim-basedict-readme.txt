* chinese-pyim-basedict README                         :README:doc:

** 简介
Chinese-pyim-basedict 是 chinese-pyim 的默认词库，词库的内容的来源:

1. libpinyin 项目的内置词库
2. chinese-pyim 用户贡献的个人词库

注意：这个词库的词条量大概在1万左右，是一个 *非常小* 得词库，只能确保 Chinese-pyim
可以正常工作，如果用户想让 chinese-pyim 更加顺手，需要添加附加的词库，
一个比较好的选择是安装 chinese-pyim-greatdict, 不过这个词库非常庞大，词条量
超过300万，不适合计算机 cpu 和内存不足的用户。另外，用户也可以使用其它方式
添加词库，具体请参考 chinese-pyim README 中的相关章节：

        https://github.com/tumashu/chinese-pyim

** 安装和使用
1. 配置melpa源，参考：http://melpa.org/#/getting-started
2. M-x package-install RET chinese-pyim-basedict RET
3. 在emacs配置文件中（比如: ~/.emacs）添加如下代码：
   #+BEGIN_EXAMPLE
   (require 'chinese-pyim-basedict)
   (chinese-pyim-basedict-enable)
   #+END_EXAMPLE

** 如何为这个项目贡献词条
Chinese-pyim 的用户，如果想让自己常用词条进入 chinese-pyim 默认词库的话，
可以运行 `pyim-contribute-words' , 然后按照它的提示操作就可以了。
