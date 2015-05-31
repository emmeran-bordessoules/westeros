# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
        ('comment', '0002_auto_20150523_1350'),
    ]

    operations = [
        migrations.CreateModel(
            name='compteur',
            fields=[
                ('id', models.AutoField(serialize=False, auto_created=True, verbose_name='ID', primary_key=True)),
                ('compteur', models.IntegerField(default=8)),
            ],
            options={
            },
            bases=(models.Model,),
        ),
    ]
