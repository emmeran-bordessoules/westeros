from django.db import models

class Departement(models.Model):
	NumDep=models.IntegerField(default=1)
	NomDep=models.CharField(max_length=200)
	
	def __str__(self):
		return self.NomDep


class Votant(models.Model):
	NumDep=models.ForeignKey('Departement')
	NumVote=models.ForeignKey('Vote')
	
	
class Vote(models.Model):
	NumVote=models.IntegerField(primary_key=True)
	Score=models.IntegerField()
	Nom=models.CharField(max_length=100, default='Jean')
	
	def __score__(self):
		return self.score
		
	def __str__(self):
		return self.Nom
