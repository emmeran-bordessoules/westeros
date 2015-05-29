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
                ('id', models.AutoField(auto_created=True, primary_key=True, verbose_name='ID', serialize=False)),
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
                ('id', models.AutoField(auto_created=True, primary_key=True, verbose_name='ID', serialize=False)),
                ('IPVotant', models.CharField(max_length=100)),
                ('NumDep', models.ForeignKey(null=True, to='vote.Departement')),
            ],
            options={
            },
            bases=(models.Model,),
        ),
        migrations.CreateModel(
            name='Vote',
            fields=[
                ('NumVote', models.IntegerField(primary_key=True, serialize=False)),
                ('Score', models.IntegerField(default=0)),
                ('NomVote', models.CharField(max_length=100)),
                ('ImgVote', models.ImageField(upload_to='static/images/')),
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
