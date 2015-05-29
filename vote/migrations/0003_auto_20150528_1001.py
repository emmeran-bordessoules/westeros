# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
        ('vote', '0002_auto_20150528_0959'),
    ]

    operations = [
        migrations.RenameField(
            model_name='scoredep',
            old_name='scoreDep',
            new_name='ScoreDep',
        ),
    ]
