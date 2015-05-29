# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
        ('vote', '0001_initial'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='vote',
            name='id',
        ),
        migrations.AlterField(
            model_name='vote',
            name='NumVote',
            field=models.ForeignKey(serialize=False, to='vote.Votant', primary_key=True),
            preserve_default=True,
        ),
    ]
