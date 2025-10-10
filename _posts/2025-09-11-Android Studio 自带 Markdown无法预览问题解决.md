---
categories: [问题解决]
title: AndroidStudio自带Markdown无法预览问题解决
date: 2025-9-11 19:59:00 +0800
pin: false
last_modified_at: 2025-9-11 19:59:00 +0800
tags: [markdown]
keywords: [markdown]
---

For all those that had issues with "Your environment does not support JCEF, cannot use Markdown Editor": this is because AndroidStudio by default uses a runtime that does not support JCEF. Here is how to fix this: Switch your AndroidStudio-Runtime to a version that supports JCEF. Go to "Help" -> "Find Action..." -> "Choose Boot Java Runtime for the IDE". In the field "New" select a runtime that has a version number at least as high as the one that is currently selected but with a description saying "... with JCEF". In my case this was e.g. the third from the top "21.0.7b805 JetBrains Runtime JBR with JCEF (bundled by default)"). Click OK - you will be asked to restart the IDE. That's it!