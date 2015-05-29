# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
        ('vote', '0002_auto_20150519_1814'),
    ]

    operations = [
        migrations.AddField(
            model_name='vote',
            name='Nom',
            field=models.TextField(default='Jean', max_length=100),
            preserve_default=True,
        ),
        migrations.AlterField(
            model_name='departement',
            name='NomDep',
            field=models.TextField(max_length=200),
            preserve_default=True,
        ),
        migrations.AlterField(
            model_name='votant',
            name='NumVote',
            field=models.ForeignKey(to='vote.Vote'),
            preserve_default=True,
        ),
        migrations.AlterField(
            model_name='vote',
            name='NumVote',
            field=models.IntegerField(serialize=False, primary_key=True),
            preserve_default=True,
        ),
    ]
