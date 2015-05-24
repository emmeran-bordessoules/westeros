# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='Article',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, primary_key=True, auto_created=True)),
                ('sujet', models.CharField(max_length=100)),
                ('auteur', models.CharField(max_length=42)),
                ('message', models.TextField(null=True)),
            ],
            options={
            },
            bases=(models.Model,),
        ),
    ]
