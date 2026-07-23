---
title: 面试
icon: fas fa-user-tie
order: 5
---

<ul class="interview-list">
  {% assign items = site.interview | sort: 'date' | reverse %}
  {% for item in items %}
    <li>
      <a href="{{ item.url | relative_url }}">{{ item.title }}</a>
      <span class="text-muted small">
        {% include datetime.html date=item.date lang=lang %}
      </span>
    </li>
  {% endfor %}
</ul>
