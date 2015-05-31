from django.shortcuts import render
from vote.models import scoreDep
from vote.views import hasard

def home(request):
	score=scoreDep.objects.order_by('NumDep','-ScoreDep')[:800:8]
	cita=hasard()
	return render(request,'carto/carto.html',{'score':score,'cita':cita})
