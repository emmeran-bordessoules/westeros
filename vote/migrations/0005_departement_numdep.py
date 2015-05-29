# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
        ('vote', '0004_auto_20150519_1852'),
    ]

    operations = [
        migrations.AddField(
            model_name='departement',
            name='NumDep',
            field=models.IntegerField(default=1),
            preserve_default=True,
        ),
    ]
