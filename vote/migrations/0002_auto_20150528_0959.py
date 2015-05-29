# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
        ('vote', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='scoreDep',
            fields=[
                ('id', models.AutoField(verbose_name='ID', primary_key=True, auto_created=True, serialize=False)),
                ('scoreDep', models.IntegerField(default=0)),
                ('NumDep', models.ForeignKey(to='vote.Departement')),
                ('VoteDep', models.ForeignKey(to='vote.Vote')),
            ],
            options={
            },
            bases=(models.Model,),
        ),
        migrations.RemoveField(
            model_name='votant',
            name='NumDep',
        ),
        migrations.RemoveField(
            model_name='votant',
            name='NumVote',
        ),
    ]
