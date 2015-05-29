# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
        ('vote', '0003_auto_20150519_1850'),
    ]

    operations = [
        migrations.AlterField(
            model_name='departement',
            name='NomDep',
            field=models.CharField(max_length=200),
            preserve_default=True,
        ),
        migrations.AlterField(
            model_name='vote',
            name='Nom',
            field=models.CharField(max_length=100, default='Jean'),
            preserve_default=True,
        ),
    ]
