# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='Departement',
            fields=[
                ('id', models.AutoField(auto_created=True, verbose_name='ID', primary_key=True, serialize=False)),
                ('NumDep', models.IntegerField(default=1)),
                ('NomDep', models.CharField(max_length=200)),
            ],
            options={
            },
            bases=(models.Model,),
        ),
        migrations.CreateModel(
            name='Votant',
            fields=[
                ('id', models.AutoField(auto_created=True, verbose_name='ID', primary_key=True, serialize=False)),
                ('NumDep', models.ForeignKey(to='vote.Departement')),
            ],
            options={
            },
            bases=(models.Model,),
        ),
        migrations.CreateModel(
            name='Vote',
            fields=[
                ('NumVote', models.IntegerField(serialize=False, primary_key=True)),
                ('Score', models.IntegerField()),
                ('Nom', models.CharField(default='Jean', max_length=100)),
            ],
            options={
            },
            bases=(models.Model,),
        ),
        migrations.AddField(
            model_name='votant',
            name='NumVote',
            field=models.ForeignKey(to='vote.Vote'),
            preserve_default=True,
        ),
    ]
