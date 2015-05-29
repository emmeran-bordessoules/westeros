from django.db import models

class Departement(models.Model):
	NumDep=models.IntegerField(default=1)
	NomDep=models.CharField(max_length=200)
	
	def __str__(self):
		return self.NomDep

class Votant(models.Model):
	IPVotant=models.CharField(max_length=100)	

class Vote(models.Model):
	NumVote=models.IntegerField(primary_key=True)
	Score=models.IntegerField(default=0)
	NomVote=models.CharField(max_length=100)
	ImgVote=models.ImageField(upload_to="static/images/")
	
	# def __score__(self):
		# return self.Score
		
	def __str__(self):
		return self.NomVote

class scoreDep(models.Model):
	VoteDep=models.ForeignKey('Vote')
	NumDep=models.ForeignKey('Departement')
	ScoreDep=models.IntegerField(default=0)
	
class voteForm(models.Model):
	formDep=models.IntegerField(default=0)
	formVote=models.IntegerField(default=0)