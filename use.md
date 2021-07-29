配置环境后，教程笔记里面有配置步骤，然后执行下面操作

安装jekyll: gem install jekyll

1、gem install bundler

2、Gemfile文件里的内容都需要执行gem install命令安装，source代表的是源，好像得翻墙可以改成http://gems.ruby-china.org/

3、删除博客根目录下的Gemfile.lock文件（如果存在的话），之后执行bundle install命令操作生成Gemfile.lock文件（这个命令在博客根目录下操作）

4、我的博客模板会出现中文编码错误，查看笔记“ruby编译scss出现invalid GBK错误”

报错 webrick https://zhuanlan.zhihu.com/p/350462079